class DooverRecordingSleeper
  getter sleeps = [] of Time::Span

  def record(span : Time::Span) : Nil
    @sleeps << span
  end

  def count : Int32
    @sleeps.size
  end
end
