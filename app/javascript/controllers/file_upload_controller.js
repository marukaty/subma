// data-controller="file-upload"
// data-file-upload-target="input"     — <input type="file"> (hidden)
// data-file-upload-target="dropzone"  — クリック/ドロップ領域
// data-file-upload-target="filename"  — 選択ファイル名表示
// data-file-upload-target="placeholder" — 未選択時のプレースホルダ
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropzone", "filename", "placeholder"]
  static classes = ["dragOver"]

  connect() {
    this.updateFilename()
  }

  // input の change 時にファイル名を反映
  onChange() {
    this.updateFilename()
  }

  // クリックで input を発火
  openPicker(event) {
    // input 自身をクリックした時は二重発火を避ける
    if (event.target === this.inputTarget) return
    this.inputTarget.click()
  }

  onDragOver(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add(...this.dragOverClasses)
  }

  onDragLeave() {
    this.dropzoneTarget.classList.remove(...this.dragOverClasses)
  }

  onDrop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove(...this.dragOverClasses)

    const files = event.dataTransfer?.files
    if (!files || files.length === 0) return

    // <input type="file"> に DataTransfer 経由で files をセット
    this.inputTarget.files = files
    this.updateFilename()
  }

  updateFilename() {
    const file = this.inputTarget.files?.[0]
    if (file) {
      this.filenameTarget.textContent = `${file.name} (${this.formatSize(file.size)})`
      this.filenameTarget.classList.remove("hidden")
      this.placeholderTarget.classList.add("hidden")
    } else {
      this.filenameTarget.textContent = ""
      this.filenameTarget.classList.add("hidden")
      this.placeholderTarget.classList.remove("hidden")
    }
  }

  formatSize(bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`
  }
}
