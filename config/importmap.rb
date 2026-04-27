# Pin npm packages by running ./bin/importmap

pin "application"
pin "auth_handler", to: "auth_handler.js"

# Firebase Web SDK は gstatic.com の ESM モジュールから直接読み込む
# JSPM 経由で vendor に置く方式は内部で動的チャンク読み込みを行うため
# importmap-rails では動作しない（idb の wrap-idb-value.js などが 404 になる）
# 参考: https://firebase.google.com/docs/web/learn-more#modular-version
pin "firebase/app", to: "https://www.gstatic.com/firebasejs/12.12.1/firebase-app.js"
pin "firebase/auth", to: "https://www.gstatic.com/firebasejs/12.12.1/firebase-auth.js"
