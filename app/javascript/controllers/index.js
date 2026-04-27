// Stimulus controllers の自動登録
import { Application } from "@hotwired/stimulus"
import TemplatePickerController from "controllers/template_picker_controller"

const application = Application.start()
application.debug = false
window.Stimulus = application

application.register("template-picker", TemplatePickerController)
