class ServiceTemplatesController < ApplicationController
  before_action :authenticate_user!

  # GET /service_templates.json
  # 登録フォームのテンプレート選択 → 自動入力で使う JSON エンドポイント
  def index
    templates = ServiceTemplate.order(:default_category, :service_name)
    render json: templates.as_json(
      only: %i[id service_name default_amount default_billing_cycle default_category icon_url]
    )
  end
end
