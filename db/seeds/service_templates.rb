# 主要 50 サブスクサービスのマスターデータ
# 各サービスにデフォルト料金・課金サイクル・カテゴリ・CSV マッチパターンを設定
# match_patterns は CSV の利用店名に対する正規表現（大文字小文字区別なし）
# 照合時は店名・パターンの両方を Unicode NFKC で正規化する（ServiceTemplate#match?）。
# そのためカナのパターンは全角で書けば、CSV 側の半角カナ（例: 「ｱﾄﾞﾋﾞ」）にも一致する。
#
# 並び順に意味がある: Tier 1（RuleClassifier）は id 昇順で最初に一致したテンプレートを採用する。
# 汎用的なパターン（例: Apple（App Store/iCloud））は、個別サービス（Apple Music 等）より後ろに置く。
#
# 通信費（携帯・回線・プロバイダの月額）はサブスクの対象外（ADR-0008）。テンプレートを置かない。
# 料金は MVP 時点の参考値。実利用ユーザーが個別に登録時に修正可能。
#
# 使い方: bin/rails db:seed (db/seeds.rb から require して呼び出す)

puts "Seeding ServiceTemplate..."

templates = [
  # === 動画・音楽 (エンタメ) ===
  { service_name: "Netflix",            default_amount: 1490, default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "NETFLIX", "ネットフリックス" ] },
  { service_name: "Spotify Premium",    default_amount: 980,  default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "SPOTIFY", "スポティファイ" ] },
  { service_name: "Apple Music",        default_amount: 1080, default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "APPLE.*MUSIC", "iTunes" ] },
  { service_name: "YouTube Premium",    default_amount: 1280, default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "YOUTUBE.*PREMIUM", "GOOGLE.*YOUTUBE" ] },
  # Amazon は「AMAZON.CO.JP」単体だと通常の買い物と区別できないため、PRIME を含むものだけに限定する
  { service_name: "Amazon Prime",       default_amount: 600,  default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "AMAZON.*PRIME", "AMZN.*PRIME" ] },
  { service_name: "Disney+",            default_amount: 990,  default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "DISNEY", "ディズニー" ] },
  { service_name: "Hulu",               default_amount: 1026, default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "HULU", "フールー" ] },
  { service_name: "U-NEXT",             default_amount: 2189, default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "U-NEXT", "ユーネクスト" ] },
  { service_name: "ABEMA Premium",      default_amount: 960,  default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "ABEMA", "アベマ" ] },
  { service_name: "DAZN",               default_amount: 4200, default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "DAZN", "ダゾーン" ] },
  { service_name: "Apple TV+",          default_amount: 900,  default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "APPLE.*TV" ] },
  { service_name: "dアニメストア",      default_amount: 550,  default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "dアニメ", "Dアニメ" ] },

  # === 読書・コンテンツ ===
  { service_name: "Kindle Unlimited",   default_amount: 980,  default_billing_cycle: :monthly, default_category: "学習",     match_patterns: [ "KINDLE.*UNLIMITED" ] },
  { service_name: "Audible",            default_amount: 1500, default_billing_cycle: :monthly, default_category: "学習",     match_patterns: [ "AUDIBLE", "オーディブル" ] },

  # === AI / 開発ツール (仕事) ===
  { service_name: "ChatGPT Plus",       default_amount: 3000, default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "OPENAI", "CHATGPT" ] },
  { service_name: "Claude Pro",         default_amount: 3000, default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "ANTHROPIC", "CLAUDE\\.AI" ] },
  { service_name: "GitHub Pro",         default_amount: 600,  default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "GITHUB" ] },
  { service_name: "GitHub Copilot",     default_amount: 1500, default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "GITHUB.*COPILOT" ] },
  { service_name: "Cursor Pro",         default_amount: 3000, default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "CURSOR" ] },
  { service_name: "Notion",             default_amount: 1500, default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "NOTION" ] },
  { service_name: "Figma",              default_amount: 1800, default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "FIGMA" ] },
  { service_name: "Slack",              default_amount: 925,  default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "SLACK" ] },
  { service_name: "Zoom Pro",           default_amount: 2125, default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "ZOOM\\." ] },
  { service_name: "Linear",             default_amount: 1200, default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "LINEAR\\.APP" ] },
  { service_name: "1Password",          default_amount: 450,  default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "1PASSWORD", "AGILEBITS" ] },
  { service_name: "Adobe Creative Cloud", default_amount: 7280, default_billing_cycle: :monthly, default_category: "仕事",   match_patterns: [ "ADOBE", "アドビ" ] },
  { service_name: "Microsoft 365",      default_amount: 1490, default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "MICROSOFT.*365", "OFFICE.*365" ] },
  { service_name: "Google Workspace",   default_amount: 816,  default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "GOOGLE.*WORKSPACE", "GSUITE" ] },

  # === ホスティング・インフラ (仕事) ===
  { service_name: "AWS",                default_amount: 0,    default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "AMAZON WEB SERVICES", "\\bAWS\\b" ] }, # 単語境界なしだと「LAWSON」に一致してしまう
  { service_name: "Vercel",             default_amount: 3000, default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "VERCEL" ] },
  { service_name: "Cloudflare",         default_amount: 750,  default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "CLOUDFLARE" ] },
  { service_name: "Heroku",             default_amount: 1000, default_billing_cycle: :monthly, default_category: "仕事",     match_patterns: [ "HEROKU" ] },

  # === ストレージ ===
  { service_name: "iCloud+ 200GB",      default_amount: 400,  default_billing_cycle: :monthly, default_category: "ストレージ", match_patterns: [ "ICLOUD", "iCLOUD\\+" ] },
  { service_name: "Google One",         default_amount: 250,  default_billing_cycle: :monthly, default_category: "ストレージ", match_patterns: [ "GOOGLE.*ONE", "GOOGLE.*STORAGE" ] },
  { service_name: "Dropbox",            default_amount: 1500, default_billing_cycle: :monthly, default_category: "ストレージ", match_patterns: [ "DROPBOX" ] },
  { service_name: "Microsoft OneDrive", default_amount: 224,  default_billing_cycle: :monthly, default_category: "ストレージ", match_patterns: [ "ONEDRIVE" ] },

  # === 学習 ===
  { service_name: "Udemy Business",     default_amount: 2000, default_billing_cycle: :monthly, default_category: "学習",     match_patterns: [ "UDEMY" ] },
  { service_name: "Duolingo Plus",      default_amount: 1300, default_billing_cycle: :monthly, default_category: "学習",     match_patterns: [ "DUOLINGO" ] },
  { service_name: "スタディサプリ",     default_amount: 2178, default_billing_cycle: :monthly, default_category: "学習",     match_patterns: [ "スタディサプリ", "STUDY SAPURI" ] },
  { service_name: "Coursera Plus",      default_amount: 6000, default_billing_cycle: :monthly, default_category: "学習",     match_patterns: [ "COURSERA" ] },
  { service_name: "Progate",            default_amount: 1490, default_billing_cycle: :monthly, default_category: "学習",     match_patterns: [ "PROGATE", "プロゲート" ] },

  # === フィットネス・健康 ===
  { service_name: "Apple Fitness+",     default_amount: 1080, default_billing_cycle: :monthly, default_category: "健康",     match_patterns: [ "APPLE.*FITNESS" ] },
  { service_name: "Nintendo Switch Online", default_amount: 306, default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "NINTENDO" ] },
  { service_name: "PlayStation Plus",   default_amount: 850,  default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "PLAYSTATION", "SONY.*PSN" ] },

  # === 食 / 生活 ===
  { service_name: "Oisix",              default_amount: 0,    default_billing_cycle: :weekly,  default_category: "生活",     match_patterns: [ "OISIX", "オイシックス" ] },

  # === その他 ===
  { service_name: "NHK 受信料",         default_amount: 1100, default_billing_cycle: :monthly, default_category: "生活",     match_patterns: [ "NHK", "日本放送協会" ] },
  { service_name: "X Premium",          default_amount: 980,  default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "TWITTER", "X PREMIUM" ] },

  # === 汎用（必ず末尾に置く） ===
  # App Store / iCloud 等の Apple の定期課金は明細上「APPLE COM BILL」とまとめて表示される。
  # Apple Music / Apple TV+ / Apple Fitness+ / iCloud+ の個別パターンに一致しなかったものだけをここで拾う。
  # 金額はサービスごとに異なるため既定額は置かない（登録時にユーザーが入力する）。
  { service_name: "Apple（App Store/iCloud）", default_amount: nil, default_billing_cycle: :monthly, default_category: "エンタメ", match_patterns: [ "APPLE COM BILL", "APPLE\\.COM/BILL" ] }
]

# 廃止したテンプレート。seed を再実行すると既存 DB からも削除する。
# Subscription は service_name を文字列で保持しており ServiceTemplate への外部キーを持たないため、
# ユーザーが登録済みのサブスクには影響しない。
deprecated_service_names = [
  # 通信費はサブスクの対象外（ADR-0008）
  "ahamo",
  "povo",
  "LINEMO",
  "楽天モバイル"
]

ServiceTemplate.transaction do
  templates.each do |attrs|
    template = ServiceTemplate.find_or_initialize_by(service_name: attrs[:service_name])
    template.assign_attributes(attrs)
    template.save!
  end

  removed = ServiceTemplate.where(service_name: deprecated_service_names).destroy_all
  puts "  -> removed #{removed.size} deprecated templates" if removed.any?
end

puts "  -> #{ServiceTemplate.count} templates seeded"
