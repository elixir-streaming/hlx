defmodule HLX.Part do
  @moduledoc """
  Module describing a partial segment in an HLS playlist.
  """

  alias ExM3U8.Tags

  @type t :: %__MODULE__{
          uri: String.t(),
          size: non_neg_integer(),
          duration: number(),
          index: non_neg_integer(),
          segment_index: non_neg_integer(),
          independent?: boolean()
        }

  defstruct [:uri, :size, :duration, :index, :segment_index, independent?: false]

  @spec new(Keyword.t()) :: t()
  def new(opts) do
    struct(__MODULE__, opts)
  end

  defimpl ExM3U8.Serializer do
    alias ExM3U8.{Serializer, Tags}

    def serialize(part) do
      Serializer.serialize(%Tags.Part{
        uri: part.uri,
        duration: part.duration,
        independent?: part.independent?
      })
    end
  end
end
