// Firebase Web SDK で Google SSO ログイン → ID トークンを Rails に POST
// ログイン成功時: /auth/sign_in に id_token を送信、200 で /dashboard へ遷移
// エラー時: ログイン画面にエラー表示

import { initializeApp } from "firebase/app"
import {
  getAuth,
  GoogleAuthProvider,
  signInWithPopup,
  signOut as firebaseSignOut
} from "firebase/auth"

function readFirebaseConfig() {
  const meta = (name) => document.querySelector(`meta[name="${name}"]`)?.content
  return {
    apiKey: meta("firebase-api-key"),
    authDomain: meta("firebase-auth-domain"),
    projectId: meta("firebase-project-id"),
    appId: meta("firebase-app-id")
  }
}

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

const app = initializeApp(readFirebaseConfig())
const auth = getAuth(app)

async function postIdTokenToRails(idToken) {
  const response = await fetch("/auth/sign_in", {
    method: "POST",
    credentials: "same-origin",
    headers: {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-CSRF-Token": csrfToken()
    },
    body: JSON.stringify({ id_token: idToken })
  })
  const data = await response.json().catch(() => ({}))
  if (!response.ok || !data.ok) {
    throw new Error(data.error || `HTTP ${response.status}`)
  }
  return data.redirect_to
}

async function signInWithGoogle() {
  const provider = new GoogleAuthProvider()
  const result = await signInWithPopup(auth, provider)
  const idToken = await result.user.getIdToken(/* forceRefresh */ true)
  const redirectTo = await postIdTokenToRails(idToken)
  window.location.href = redirectTo || "/dashboard"
}

async function signOutFromBoth() {
  await fetch("/auth/sign_out", {
    method: "DELETE",
    credentials: "same-origin",
    headers: {
      "Accept": "application/json",
      "X-CSRF-Token": csrfToken()
    }
  })
  await firebaseSignOut(auth)
  window.location.href = "/login"
}

document.addEventListener("DOMContentLoaded", () => {
  const errorBox = document.getElementById("auth-error")

  document.getElementById("sign-in-google")?.addEventListener("click", async () => {
    if (errorBox) errorBox.textContent = ""
    try {
      await signInWithGoogle()
    } catch (error) {
      console.error("[auth] sign-in failed:", error)
      if (errorBox) errorBox.textContent = `ログインに失敗しました: ${error.message}`
    }
  })

  document.getElementById("sign-out")?.addEventListener("click", async (event) => {
    event.preventDefault()
    try {
      await signOutFromBoth()
    } catch (error) {
      console.error("[auth] sign-out failed:", error)
      window.location.href = "/login"
    }
  })
})
