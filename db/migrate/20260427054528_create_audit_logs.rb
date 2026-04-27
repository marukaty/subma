class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      # 認証前イベント（sign_in 失敗等）も記録するため null 許容
      t.references :user, null: true, foreign_key: true
      t.string :action, null: false
      t.string :resource_type
      t.bigint :resource_id
      t.string :ip_address, limit: 45  # IPv6 最大長
      t.string :user_agent, limit: 500

      t.timestamps
    end

    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
  end
end
