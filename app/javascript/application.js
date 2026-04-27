// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "auth_handler"
import "controllers"

// Chartkick + Chart.js は Dashboard でグラフを描くためグローバル登録
import "charts"
