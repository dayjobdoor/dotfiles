# Tools/Recommend

- 簡潔な日本語で回答する
- command `jj` があれば `git` を代換する。ただし `jj` は git の hook（gitleaks の pre-commit など）を実行しないので、`core.hooksPath` が設定されたリポジトリでは commit に `git` を使う
- command `ax` があれば `curl` を一部代換
- command `graphify` と `./graphify-out` があれば 活用して定期的に更新する
