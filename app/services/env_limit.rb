# 上限値を環境変数から読む（CSV の行数・AI に送る行数など）。
#
# 未設定・数値でない・下限より小さいときは既定値を使う（設定ミスで上限が外れないように）。
#
# [ai-assisted]
module EnvLimit
  # @param name [String] 環境変数名
  # @param default [Integer] 既定値
  # @param min [Integer] 受け付ける最小値（AI の上限は 0 = AI を使わない、を許す）
  # @return [Integer]
  def self.integer(name, default:, min: 1)
    value = ENV[name].to_s.strip
    return default if value.empty?

    number = Integer(value, 10)
    number >= min ? number : default
  rescue ArgumentError
    default
  end
end
