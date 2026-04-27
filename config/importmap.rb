# Pin npm packages by running ./bin/importmap

pin "application"
pin "auth_handler", to: "auth_handler.js"
pin "controllers", to: "controllers/index.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Firebase Web SDK は gstatic.com の ESM モジュールから直接読み込む
# JSPM 経由で vendor に置く方式は内部で動的チャンク読み込みを行うため
# importmap-rails では動作しない（idb の wrap-idb-value.js などが 404 になる）
# 参考: https://firebase.google.com/docs/web/learn-more#modular-version
pin "firebase/app", to: "https://www.gstatic.com/firebasejs/12.12.1/firebase-app.js"
pin "firebase/auth", to: "https://www.gstatic.com/firebasejs/12.12.1/firebase-auth.js"
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2
pin "@hotwired/turbo-rails", to: "@hotwired--turbo-rails.js" # @8.0.23
pin "@hotwired/turbo", to: "@hotwired--turbo.js" # @8.0.23
pin "@rails/actioncable/src", to: "@rails--actioncable--src.js" # @8.1.300
