module Csv
  # アップロードされた CSV のバイト列を UTF-8 の文字列にする（検証と取り込みで共通）。
  #
  # カード会社の CSV は UTF-8（BOM 付きを含む）と Shift_JIS 系が混在する。
  # まず UTF-8 として読み、だめなら Windows-31J（CP932）として読む。
  # Windows-31J は Shift_JIS の上位互換で、Windows で作られた CSV に含まれる
  # ①・㈱・髙 などの機種依存文字も正しく変換できる（Shift_JIS で読むとこれらが「?」に置き換わる）。
  #
  # 先頭の BOM は取り除く（残すと 1 行目が「\uFEFF"利用日"」となり、CSV の解釈に失敗するため）。
  #
  # [ai-assisted]
  module TextDecoder
    UTF8_BOM = "\uFEFF".freeze
    LEGACY_ENCODING = ::Encoding::Windows_31J

    module_function

    # @param bytes [String] ファイルの中身（文字コードは問わない）
    # @param strict [Boolean] true なら、どちらの文字コードとしても正しく読めないときに nil を返す。
    #   false なら、読めないバイトを置き換えて変換する（取り込み時）
    # @return [String, nil] UTF-8 の文字列
    def decode(bytes, strict: false)
      utf8 = bytes.b.force_encoding(::Encoding::UTF_8)
      return utf8.delete_prefix(UTF8_BOM) if utf8.valid_encoding?

      legacy = bytes.b.force_encoding(LEGACY_ENCODING)
      return legacy.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace) unless strict
      return nil unless legacy.valid_encoding?

      legacy.encode(::Encoding::UTF_8)
    rescue EncodingError
      nil
    end
  end
end
