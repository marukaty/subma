# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_27_073505) do
  create_table "audit_logs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.string "ip_address", limit: 45
    t.bigint "resource_id"
    t.string "resource_type"
    t.datetime "updated_at", null: false
    t.string "user_agent", limit: 500
    t.bigint "user_id"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "service_templates", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "default_amount", precision: 10, scale: 2
    t.integer "default_billing_cycle", default: 0, null: false
    t.string "default_category"
    t.string "icon_url"
    t.json "match_patterns"
    t.string "service_name", null: false
    t.datetime "updated_at", null: false
    t.index ["default_category"], name: "index_service_templates_on_default_category"
    t.index ["service_name"], name: "index_service_templates_on_service_name", unique: true
  end

  create_table "subscriptions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.integer "billing_cycle", default: 0, null: false
    t.date "cancelled_at"
    t.string "category"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "JPY", null: false
    t.text "memo"
    t.date "next_billing_date"
    t.string "payment_method"
    t.string "service_name", null: false
    t.integer "source", default: 0, null: false
    t.date "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["next_billing_date"], name: "index_subscriptions_on_next_billing_date"
    t.index ["user_id", "status"], name: "index_subscriptions_on_user_id_and_status"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email", null: false
    t.string "firebase_uid", null: false
    t.boolean "notification_enabled", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email"
    t.index ["firebase_uid"], name: "index_users_on_firebase_uid", unique: true
  end

  add_foreign_key "audit_logs", "users"
  add_foreign_key "subscriptions", "users"
end
