# lk-branch-create

This is designed to sync the release branches from LabKey with another repo.  It follows this logic:

- You provide the source and destination repos.
- You provide a source_branch_prefix (i.e. 'release'). Any source branch beginning with this repo will be considered.
- You provide a destination_branch_prefix (i.e. 'discvr-'). This is used when inspecting and/or creating destination branches.  
- If you have the source_branch_prefix 'release' and destination_branch_prefix of 'discvr-', then the source branch with name release19.1 would be converted to discvr-19.1.
- The script will query the destination repo to find the existing branch matching the destination_branch_prefix with the highest version (i.e. discvr-19.2 would be higher than discvr-19.1)
- The script iterates each matching source branch. Next:
- If the version of this branch is less than the highest existing destination branch, it is ignored.  This will allow destination branches to delete older version branches without them being re-created.
- If the target destination branch does not already exist and the version is higher than the highest existing, it will be created from the source branch.
