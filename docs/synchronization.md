# GitHub, local Windows, and Atlas synchronization

GitHub `main` is canonical for source code, configuration templates, tests, and documentation. Local Windows and Atlas are execution checkouts and should be synchronized fast-forward-only.

```powershell
git fetch origin
git switch main
git merge --ff-only origin/main
git status -sb
```

After a reviewed production commit is pushed, run the same sequence on Atlas after loading the validated module stack. Commit source changes locally, push them to GitHub, and fetch the canonical commit on Atlas; do not copy source-only changes directly from Atlas. Record GitHub, local, and Atlas commits in the production manifest. Do not force-push `main`.
