# db/seeds/ 配下のシードを順次読み込む
# 各シードは idempotent（find_or_initialize_by で重複防止）
require_relative "seeds/service_templates"
