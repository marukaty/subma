class SubscriptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_subscription, only: %i[edit update destroy pause resume cancel]

  def index
    @subscriptions = current_user.subscriptions.order(:next_billing_date, :service_name)
    @view_mode = params[:view] == "card" ? "card" : "table"
  end

  def new
    @subscription = current_user.subscriptions.new(
      currency: "JPY",
      billing_cycle: :monthly,
      status: :active,
      source: :manual,
      next_billing_date: Date.current.next_month
    )
  end

  def create
    @subscription = current_user.subscriptions.new(subscription_params)
    @subscription.source = :manual
    @audit_resource = @subscription

    if @subscription.save
      redirect_to subscriptions_path, notice: "「#{@subscription.service_name}」を登録しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @audit_resource = @subscription
    if @subscription.update(subscription_params)
      redirect_to subscriptions_path, notice: "「#{@subscription.service_name}」を更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @audit_resource = @subscription
    @subscription.destroy
    redirect_to subscriptions_path, notice: "「#{@subscription.service_name}」を削除しました"
  end

  def pause
    @audit_resource = @subscription
    @subscription.status_paused!
    redirect_to subscriptions_path, notice: "「#{@subscription.service_name}」を一時停止しました"
  end

  def resume
    @audit_resource = @subscription
    @subscription.status_active!
    redirect_to subscriptions_path, notice: "「#{@subscription.service_name}」を再開しました"
  end

  def cancel
    @audit_resource = @subscription
    @subscription.status_cancelled!
    redirect_to subscriptions_path, notice: "「#{@subscription.service_name}」を解約済みにしました"
  end

  private

  def set_subscription
    @subscription = current_user.subscriptions.find(params[:id])
  end

  def subscription_params
    params.expect(
      subscription: [
        :service_name, :amount, :currency, :billing_cycle,
        :next_billing_date, :payment_method, :category, :status,
        :started_at, :memo
      ]
    )
  end
end
