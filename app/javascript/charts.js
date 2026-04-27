// Chartkick + Chart.js のブリッジ初期化
// chartkick gem の view helper (line_chart, pie_chart 等) は
// グローバルの window.Chartkick を参照するためここで露出する。
//
// chart.js/auto は LineController / PieController などを事前登録した
// 全部入りビルド。CDN ESM なので importmap で URL pin している。

import Chart from "chart.js/auto"
import Chartkick from "chartkick"

Chartkick.use(Chart)

window.Chartkick = Chartkick
