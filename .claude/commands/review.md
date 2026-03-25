---
description: Review the current branch diff for issues before merging
---
## Changes to Review

!`git diff --name-only main...HEAD`

## Detailed Diff

!`git diff main...HEAD`

Review the above changes for:
1. Code quality issues and Swift best practices
2. Memory leaks or retain cycles in closures
3. Thread safety (main actor isolation, background work)
4. Missing error handling
5. UI/UX consistency with the existing dark blue-green design
