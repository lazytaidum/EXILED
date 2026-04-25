# Git Notes

This project should usually be worked on from `master`.

## Start Of Session

Run:

```powershell
git switch master
git pull
git status
```

You want to see:

```text
On branch master
```

## During Work

Useful checks:

```powershell
git branch --show-current
git status
git diff
```

What they do:

- `git branch --show-current` shows your current branch.
- `git status` shows changed files and whether you are on `master`.
- `git diff` shows file changes before committing.

## Save Your Work

When you are ready to save changes to Git:

```powershell
git add .
git commit -m "Short note about what changed"
git push
```

## If Git Looks Weird

If you ever see a message about `HEAD detached`, run:

```powershell
git switch master
```

Then check again:

```powershell
git status
```

## Important For Rojo

Git only tracks files that are actually saved into this repo.

For this project, new Roblox Studio code should end up in these folders:

- `src/client/UI`
- `src/client/Controllers`
- `src/shared/Utility`
- `src/server/Services`

If something only exists in Studio and was never saved into `src/...`, Git will not see it.

## Simple Daily Routine

1. `git switch master`
2. `git pull`
3. Edit files in `src/...`
4. `git status`
5. `git add .`
6. `git commit -m "what changed"`
7. `git push`

## Good Habit

Before closing for the day, run:

```powershell
git status
```

If it shows changed files, either commit them or make sure you know they are still only local.
