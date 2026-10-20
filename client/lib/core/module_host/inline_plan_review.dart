import 'collection_store.dart';
import 'plan_confirmation.dart';

/// One native confirmation click authorizes only the frozen plan it displayed.
/// A tree declaration alone never constructs or grants this capability.
class InlinePlanApproval {
  InlinePlanApproval(this.plan);

  final ChangePlan plan;
  bool _used = false;

  bool allows(ChangePlan candidate, PlanConfirmation? confirmation) {
    if (_used) return false;
    _used = true;
    return identical(plan, candidate) && confirmation?.acknowledgement == null;
  }
}
