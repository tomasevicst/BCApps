# Sample review management

This synthetic app demonstrates a review-reuse policy for evaluation tests.

## Behavior

`Review Management`.`Get or Create Review` reuses an existing open review for the same source document. Closed reviews are never reused. If no open review exists, the procedure creates one.

## Evidence

- [Review management](src/ReviewManagement.Codeunit.al)