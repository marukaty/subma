// data-controller="csv-review"
// data-csv-review-target="row"  — 各行のチェックボックス
// data-csv-review-target="selectAll"  — ヘッダの全選択チェックボックス
// data-csv-review-target="submitBtn"  — 登録ボタン（カウント表示用）
//
// 役割:
// 1) 全選択チェックボックスで全行を一括 ON/OFF
// 2) チェック数に応じてボタンの label を「選択した N 件を登録する」に更新
// 3) submit 直前に現在のチェック数で confirm ダイアログを出す（サーバー render 時の数ではなく実際の数）
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "selectAll", "submitBtn"]

  connect() {
    this.refreshLabel()
  }

  toggleAll() {
    this.rowTargets.forEach((r) => { r.checked = this.selectAllTarget.checked })
    this.refreshLabel()
  }

  rowChanged() {
    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = this.rowTargets.every((r) => r.checked)
    }
    this.refreshLabel()
  }

  // submit 直前に呼ばれる。現在のチェック数で確認 + 0 件なら送信中止。
  confirmSubmit(event) {
    const count = this.checkedCount()
    if (count === 0) {
      event.preventDefault()
      alert("登録する行を 1 つ以上選択してください")
      return
    }
    if (!window.confirm(`${count} 件をサブスクとして登録します。よろしいですか？`)) {
      event.preventDefault()
    }
  }

  checkedCount() {
    return this.rowTargets.filter((r) => r.checked).length
  }

  refreshLabel() {
    if (!this.hasSubmitBtnTarget) return
    const count = this.checkedCount()
    this.submitBtnTarget.value = `選択した ${count} 件を登録する`
    this.submitBtnTarget.disabled = count === 0
    this.submitBtnTarget.classList.toggle("opacity-50", count === 0)
    this.submitBtnTarget.classList.toggle("cursor-not-allowed", count === 0)
  }
}
