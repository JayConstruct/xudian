/* Message-only ABI. No JSValue or engine pointer crosses this boundary. */
#include "quickjs.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#ifdef _WIN32
#include <windows.h>
#define EXPORT __declspec(dllexport)
typedef CRITICAL_SECTION Mutex;
#define LOCK(m) EnterCriticalSection(m)
#define UNLOCK(m) LeaveCriticalSection(m)
#else
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>
#define EXPORT __attribute__((visibility("default")))
typedef pthread_mutex_t Mutex;
#define LOCK(m) pthread_mutex_lock(m)
#define UNLOCK(m) pthread_mutex_unlock(m)
#endif

typedef struct Message { char *text; struct Message *next; } Message;
typedef struct Source { char *path, *text; struct Source *next; } Source;
typedef struct Worker {
    Mutex mutex;
#ifdef _WIN32
    CONDITION_VARIABLE wake;
#else
    pthread_cond_t wake;
#endif
    Message *in_first, *in_last, *out_first, *out_last;
    Source *sources;
    JSRuntime *rt; JSContext *ctx;
    double deadline;
    int started; size_t memory_limit, in_bytes, out_bytes;
#ifdef _WIN32
    HANDLE thread; volatile LONG cancelled;
#else
    pthread_t thread; atomic_int cancelled;
#endif
} Worker;
static char *copy(const char *s) { size_t n=strlen(s)+1; char *p=malloc(n); if(p) memcpy(p,s,n); return p; }
static double now_ms(void) {
#ifdef _WIN32
    return (double)GetTickCount64();
#else
    struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t);
    return t.tv_sec*1000.0+t.tv_nsec/1000000.0;
#endif
}
static int cancelled(Worker *w) {
#ifdef _WIN32
    return InterlockedCompareExchange(&w->cancelled,0,0);
#else
    return atomic_load(&w->cancelled);
#endif
}
static int push(Worker *w, int output, const char *s) {
    size_t n=strlen(s)+1;
    LOCK(&w->mutex);
    size_t *bytes=output?&w->out_bytes:&w->in_bytes;
    if(n>2*1024*1024 || *bytes+n>4*1024*1024) { UNLOCK(&w->mutex); return 0; }
    Message *m=calloc(1,sizeof(*m)); if(!m) { UNLOCK(&w->mutex); return 0; }
    m->text=copy(s); if(!m->text) { free(m); UNLOCK(&w->mutex); return 0; }
    *bytes+=n;
    Message **first=output?&w->out_first:&w->in_first;
    Message **last=output?&w->out_last:&w->in_last;
    if(*last) (*last)->next=m; else *first=m; *last=m;
    if(!output) {
#ifdef _WIN32
        WakeConditionVariable(&w->wake);
#else
        pthread_cond_signal(&w->wake);
#endif
    }
    UNLOCK(&w->mutex); return 1;
}
static char *pop(Worker *w, int output) {
    LOCK(&w->mutex);
    Message **first=output?&w->out_first:&w->in_first;
    Message **last=output?&w->out_last:&w->in_last;
    Message *m=*first; if(m) { if(output) w->out_bytes-=strlen(m->text)+1; else w->in_bytes-=strlen(m->text)+1; *first=m->next; if(!*first) *last=NULL; }
    UNLOCK(&w->mutex);
    if(!m) return NULL; char *s=m->text; free(m); return s;
}
static int interrupt(JSRuntime *rt, void *opaque) {
    Worker *w=opaque; return cancelled(w) || now_ms()>w->deadline;
}
static JSValue send_message(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv) {
    Worker *w=JS_GetContextOpaque(ctx);
    const char *s=argc?JS_ToCString(ctx,argv[0]):NULL;
    if(!s) return JS_EXCEPTION;
    if(strlen(s)>2*1024*1024) { JS_FreeCString(ctx,s); return JS_ThrowRangeError(ctx,"Message too large"); }
    int ok=push(w,1,s); JS_FreeCString(ctx,s); return ok?JS_UNDEFINED:JS_ThrowRangeError(ctx,"Host message queue limit exceeded");
}
/* Reject OS modules, absolute paths, backslashes and traversal. Relative ESM
   resolution is performed within the immutable package's registered files. */
static char *normalize(JSContext *ctx,const char *base,const char *name,void *opaque) {
    char input[1024], path[1024];
    if(!strcmp(name,"@xudian/sdk")) return js_strdup(ctx,name);
    if(*name=='/' || strchr(name,'\\') || strchr(name,':')) goto invalid;
    size_t prefix=0;
    if(!strncmp(name,"./",2) || !strncmp(name,"../",3)) {
        const char *slash=strrchr(base,'/');
        prefix=slash?(size_t)(slash-base+1):0;
    }
    if(prefix+strlen(name)>=sizeof(input)) goto invalid;
    memcpy(input,base,prefix); strcpy(input+prefix,name);
    size_t length=0;
    const char *start=input;
    while(*start) {
        const char *end=strchr(start,'/');
        size_t count=end?(size_t)(end-start):strlen(start);
        if(!count) goto invalid;
        if(count==1 && start[0]=='.') { /* skip current directory */ }
        else if(count==2 && start[0]=='.' && start[1]=='.') {
            if(!length) goto invalid;
            while(length && path[length-1]!='/') --length;
            if(length) --length;
        } else {
            if(length) path[length++]='/';
            memcpy(path+length,start,count); length+=count;
        }
        if(!end) break;
        start=end+1;
    }
    if(!length) goto invalid;
    path[length]=0;
    return js_strdup(ctx,path);
invalid:
    JS_ThrowReferenceError(ctx,"Forbidden module specifier"); return NULL;
}
static JSModuleDef *load(JSContext *ctx,const char *name,void *opaque) {
    Worker *w=opaque;
    for(Source *s=w->sources;s;s=s->next) if(!strcmp(name,s->path)) {
        JSValue v=JS_Eval(ctx,s->text,strlen(s->text),name,JS_EVAL_TYPE_MODULE|JS_EVAL_FLAG_COMPILE_ONLY);
        if(JS_IsException(v)) return NULL;
        JSModuleDef *m=JS_VALUE_GET_PTR(v); JS_FreeValue(ctx,v); return m;
    }
    JS_ThrowReferenceError(ctx,"Module is not registered: %s",name); return NULL;
}
static void error_message(Worker *w) {
    JSValue e=JS_GetException(w->ctx);
    const char *s=JS_ToCString(w->ctx,e);
    JSValue obj=JS_NewObject(w->ctx);
    JS_SetPropertyStr(w->ctx,obj,"fatal",JS_NewString(w->ctx,s?s:"JavaScript execution failed"));
    JSValue json=JS_JSONStringify(w->ctx,obj,JS_UNDEFINED,JS_UNDEFINED);
    const char *j=JS_ToCString(w->ctx,json); if(j) { push(w,1,j); JS_FreeCString(w->ctx,j); }
    if(s) JS_FreeCString(w->ctx,s); JS_FreeValue(w->ctx,e); JS_FreeValue(w->ctx,obj); JS_FreeValue(w->ctx,json);
}
#ifdef _WIN32
static DWORD WINAPI run(void *arg) {
#else
static void *run(void *arg) {
#endif
    Worker *w=arg;
    w->rt=JS_NewRuntime();
    if(!w->rt) { push(w,1,"{\"fatal\":\"Runtime allocation failed\"}"); goto done; }
    JS_SetMemoryLimit(w->rt,w->memory_limit); JS_SetMaxStackSize(w->rt,512*1024);
    JS_SetInterruptHandler(w->rt,interrupt,w); JS_SetModuleLoaderFunc(w->rt,normalize,load,w);
    w->ctx=JS_NewContext(w->rt); if(!w->ctx) goto done;
    JS_SetContextOpaque(w->ctx,w);
    JSValue global=JS_GetGlobalObject(w->ctx);
    JS_SetPropertyStr(w->ctx,global,"__send",JS_NewCFunction(w->ctx,send_message,"__send",1));
    JS_FreeValue(w->ctx,global);
    while(!cancelled(w)) {
        char *code=pop(w,0); if(!code) {
            LOCK(&w->mutex);
            while(!w->in_first && !cancelled(w)) {
#ifdef _WIN32
                SleepConditionVariableCS(&w->wake,&w->mutex,INFINITE);
#else
                pthread_cond_wait(&w->wake,&w->mutex);
#endif
            }
            UNLOCK(&w->mutex); continue;
        }
        w->deadline=now_ms()+1000;
        JSValue result=JS_Eval(w->ctx,code,strlen(code),"host-message",JS_EVAL_TYPE_GLOBAL);
        free(code);
        if(JS_IsException(result)) { JS_FreeValue(w->ctx,result); error_message(w); break; }
        JS_FreeValue(w->ctx,result);
        JSContext *job_ctx;
        int status;
        while((status=JS_ExecutePendingJob(w->rt,&job_ctx))>0) {
            if(interrupt(w->rt,w)) { push(w,1,"{\"fatal\":\"Execution interrupted\"}"); goto done; }
        }
        if(status<0) { error_message(w); break; }
    }
done:
    if(w->ctx) JS_FreeContext(w->ctx);
    if(w->rt) JS_FreeRuntime(w->rt);
    w->ctx=NULL; w->rt=NULL;
    push(w,1,"{\"closed\":true}");
    return 0;
}
EXPORT void *xm_create(int64_t memory_limit) {
    Worker *w=calloc(1,sizeof(*w)); if(!w) return NULL; w->memory_limit=(size_t)memory_limit;
#ifdef _WIN32
    InitializeCriticalSection(&w->mutex); InitializeConditionVariable(&w->wake);
#else
    pthread_mutex_init(&w->mutex,NULL); pthread_cond_init(&w->wake,NULL); atomic_init(&w->cancelled,0);
#endif
    return w;
}
EXPORT int xm_add_file(void *handle,const char *path,const char *text) {
    Worker *w=handle; if(w->started) return 0;
    Source *s=calloc(1,sizeof(*s)); if(!s) return 0;
    s->path=copy(path); s->text=copy(text); if(!s->path || !s->text) { free(s->path); free(s->text); free(s); return 0; } s->next=w->sources; w->sources=s; return 1;
}
EXPORT int xm_start(void *handle) {
    Worker *w=handle; if(w->started) return 0;
#ifdef _WIN32
    w->thread=CreateThread(NULL,8*1024*1024,run,w,0,NULL); w->started=w->thread!=NULL; return w->started;
#else
    w->started=pthread_create(&w->thread,NULL,run,w)==0; return w->started;
#endif
}
EXPORT void xm_send(void *handle,const char *message) { push(handle,0,message); }
EXPORT char *xm_poll(void *handle) { return pop(handle,1); }
EXPORT void xm_free_message(void *message) { free(message); }
EXPORT void xm_cancel(void *handle) {
    Worker *w=handle;
#ifdef _WIN32
    InterlockedExchange(&w->cancelled,1);
#else
    atomic_store(&w->cancelled,1);
#endif
    LOCK(&w->mutex);
#ifdef _WIN32
    WakeAllConditionVariable(&w->wake);
#else
    pthread_cond_broadcast(&w->wake);
#endif
    UNLOCK(&w->mutex);
}
EXPORT void xm_destroy(void *handle) {
    Worker *w=handle; xm_cancel(w);
    if(w->started) {
#ifdef _WIN32
        WaitForSingleObject(w->thread,INFINITE); CloseHandle(w->thread);
#else
        pthread_join(w->thread,NULL);
#endif
    }
    char *s; while((s=pop(w,0))) free(s); while((s=pop(w,1))) free(s);
    Source *src=w->sources; while(src) { Source *next=src->next; free(src->path); free(src->text); free(src); src=next; }
#ifdef _WIN32
    DeleteCriticalSection(&w->mutex);
#else
    pthread_cond_destroy(&w->wake); pthread_mutex_destroy(&w->mutex);
#endif
    free(w);
}
