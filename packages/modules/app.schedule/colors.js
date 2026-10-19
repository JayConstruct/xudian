// Derive presentation colors without changing course records or import baselines.
// Existing default-blue records have no provenance. Treat that former default
// as automatic unless an explicit choice is recorded; keep all other palettes.
export function customCourseColor(course) {
  if(course.colorMode==='auto') return '';
  const saved=typeof course.color==='string'?course.color.trim():'';
  let color=/^#[0-9a-f]{6}$/i.test(saved)?saved:'';
  if(Number.isInteger(course.color)&&course.color>=0&&course.color<=0xffffffff) {
    color='#'+(course.color&0xffffff).toString(16).padStart(6,'0');
  }
  return course.colorMode!=='custom'&&color.toLowerCase()==='#486da4'?'':color;
}
export function courseColor(course) {
  const saved=customCourseColor(course);
  if(saved) return saved;
  const key=String(course.id||JSON.stringify([course.timetableId||'',course.code||course.name||'']));
  let hash=2166136261;
  for(let i=0;i<key.length;i++) hash=Math.imul(hash^key.charCodeAt(i),16777619)>>>0;
  // Avalanche nearby IDs before mapping into a continuous color space. No
  // palette index means additional courses do not cycle through a short list.
  hash=Math.imul(hash^(hash>>>16),0x7feb352d)>>>0;
  hash=Math.imul(hash^(hash>>>15),0x846ca68b)>>>0;
  hash=(hash^(hash>>>16))>>>0;
  const hue=(hash%360000)/1000,saturation=(52+((hash>>>12)%1300)/100)/100;
  const lightness=(43+((hash>>>21)%800)/100)/100;
  const chroma=(1-Math.abs(2*lightness-1))*saturation;
  const secondary=chroma*(1-Math.abs((hue/60)%2-1)),offset=lightness-chroma/2;
  const rgb=hue<60?[chroma,secondary,0]:hue<120?[secondary,chroma,0]:hue<180?[0,chroma,secondary]:hue<240?[0,secondary,chroma]:hue<300?[secondary,0,chroma]:[chroma,0,secondary];
  return '#'+rgb.map(channel=>Math.round((channel+offset)*255).toString(16).padStart(2,'0')).join('');
}
