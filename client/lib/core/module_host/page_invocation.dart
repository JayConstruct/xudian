import 'collection_store.dart';
import 'service_ref.dart';
import 'plan_confirmation.dart';
import 'native_command_approval.dart';

class PageReplayability {
  PageReplayability(this.safe);
  bool safe;
  int pendingBridges = 0;
  void markUnsafe() => safe = false;
}

/// Native, gesture-scoped review policy. Scripts cannot supply this callback.
typedef PagePlanReview = bool Function(
  ServiceRef reference,
  Object? input,
  ChangePlan plan,
  PlanConfirmation? confirmation,
);

/// Native approval for an exact frozen plan already displayed by the page.
/// Unlike service-specific gestures this also supports adopted provider plans.
typedef InlinePagePlanReview = bool Function(
  ChangePlan plan,
  PlanConfirmation? confirmation,
);

/// One queued page call owns all temporary authority and read tracking.
/// Async bridges capture this object instead of borrowing the next call's state.
class PageInvocation {
  PageInvocation({
    required this.readOnly,
    required this.reads,
    required this.replayability,
    required this.review,
    required this.inlineReview,
    required this.commandIsCurrent,
    required this.onCommit,
  });
  bool active = true;
  void close() {
    active = false;
    review = null;
    commandApproval = null;
  }

  final bool readOnly;
  final Set<String>? reads;
  final PageReplayability replayability;
  PagePlanReview? review;
  final InlinePagePlanReview? inlineReview;
  final bool Function()? commandIsCurrent;
  final void Function(ChangePlan)? onCommit;
  NativeCommandApproval? commandApproval;
}
