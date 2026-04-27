// テンプレート選択 → フォーム自動入力
// data-controller="template-picker"
// data-template-picker-target="select" — <select> 要素
// data-template-picker-target="serviceName/amount/billingCycle/category" — 自動入力先 input/select
// data-template-picker-url-value — GET /service_templates.json の URL

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "serviceName", "amount", "billingCycle", "category"]
  static values = { url: String }

  async connect() {
    if (!this.hasSelectTarget || !this.urlValue) return

    try {
      const response = await fetch(this.urlValue, { headers: { "Accept": "application/json" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const templates = await response.json()
      this.templates = templates

      // 「-- テンプレートから選ぶ --」をデフォルトに
      const placeholder = document.createElement("option")
      placeholder.value = ""
      placeholder.textContent = "-- テンプレートから選ぶ（任意） --"
      this.selectTarget.appendChild(placeholder)

      // カテゴリでグルーピング
      const byCategory = templates.reduce((acc, t) => {
        const key = t.default_category || "その他"
        ;(acc[key] ||= []).push(t)
        return acc
      }, {})

      Object.entries(byCategory).forEach(([category, items]) => {
        const group = document.createElement("optgroup")
        group.label = category
        items.forEach((t) => {
          const opt = document.createElement("option")
          opt.value = t.id
          opt.textContent = t.service_name
          group.appendChild(opt)
        })
        this.selectTarget.appendChild(group)
      })
    } catch (error) {
      console.warn("[template-picker] failed to load templates:", error)
    }
  }

  apply(event) {
    const id = event.target.value
    if (!id || !this.templates) return

    const tpl = this.templates.find((t) => String(t.id) === String(id))
    if (!tpl) return

    // テンプレートが選択されたら毎回フォームの該当項目を上書きする
    // （ユーザーが手で書き換えた値も新しいテンプレートで置き換わる）
    if (this.hasServiceNameTarget) this.serviceNameTarget.value = tpl.service_name || ""
    if (this.hasAmountTarget) this.amountTarget.value = tpl.default_amount ?? ""
    if (this.hasBillingCycleTarget && tpl.default_billing_cycle) this.billingCycleTarget.value = tpl.default_billing_cycle
    if (this.hasCategoryTarget) this.categoryTarget.value = tpl.default_category || ""
  }
}
