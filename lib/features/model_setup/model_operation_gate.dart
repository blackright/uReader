class ModelOperationGate {
  bool active = false;
  bool enter() {
    if (active) return false;
    active = true;
    return true;
  }

  void leave() {
    active = false;
  }
}
