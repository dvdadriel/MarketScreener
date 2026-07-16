class AnalysisController < ApplicationController
  def show
    @symbol = params[:symbol].to_s.strip
    if @symbol.present?
      @result = DeepAnalysisService.new(@symbol).call
    end
  end
end
