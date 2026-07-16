class IdxUniverseController < ApplicationController
  def show
    @tickers      = IdxUniverseService.all
    @source       = IdxUniverseService.source
    @uploaded_at  = IdxUniverseService.custom_uploaded_at
  end

  def create
    content = if params[:file].present?
      params[:file].read
    else
      params[:tickers].to_s
    end

    tickers = IdxUniverseService.save_custom(content)
    redirect_to idx_universe_path, notice: "Uploaded #{tickers.size} tickers. Active immediately."
  rescue => e
    redirect_to idx_universe_path, alert: "Upload failed: #{e.message}"
  end

  def download
    tickers = IdxUniverseService.all
    send_data tickers.join("\n"), filename: "idx_universe_#{Date.current}.txt", type: "text/plain"
  end

  def destroy
    IdxUniverseService.clear_custom!
    redirect_to idx_universe_path, notice: "Custom list cleared. Reverted to IDX API."
  end
end
