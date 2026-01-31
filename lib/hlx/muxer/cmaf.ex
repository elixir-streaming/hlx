defmodule HLX.Muxer.CMAF do
  @moduledoc """
  Module implementing `HLX.Muxer` that mux media data into fmp4 fragments.
  """

  @behaviour HLX.Muxer

  alias ExMP4.{Box, Track}

  @ftyp %Box.Ftyp{major_brand: "iso5", minor_version: 512, compatible_brands: ["iso6", "mp41"]}
  @mdat_header_size 8

  @type t :: %__MODULE__{
          tracks: %{non_neg_integer() => ExMP4.Track.t()},
          header: ExMP4.Box.t(),
          current_fragments: map(),
          fragments: [binary()],
          part_duration: map()
        }

  defstruct [:tracks, :header, :current_fragments, :fragments, :part_duration]

  @impl true
  def init(tracks) do
    tracks = Map.new(tracks, &{&1.id, HLX.Track.to_mp4_track(&1)})

    %__MODULE__{
      tracks: tracks,
      header: build_header(Map.values(tracks)),
      current_fragments: new_fragments(tracks),
      fragments: [],
      part_duration: Map.new(tracks, fn {id, _track} -> {id, 0} end)
    }
  end

  @impl true
  def get_init_header(state) do
    Box.serialize([@ftyp, state.header])
  end

  @impl true
  def push(sample, state) do
    fragments =
      Map.update!(state.current_fragments, sample.track_id, fn {traf, data} ->
        {Box.Traf.store_sample(traf, sample), [sample.payload | data]}
      end)

    %{state | current_fragments: fragments}
  end

  @impl true
  def push_parts(parts, state) do
    moof = %Box.Moof{mfhd: %Box.Mfhd{sequence_number: 0}}
    mdat = %Box.Mdat{content: []}

    trafs =
      Map.new(state.part_duration, fn {id, duration} ->
        traf = %Box.Traf{
          tfhd: %Box.Tfhd{track_id: id},
          tfdt: %Box.Tfdt{base_media_decode_time: duration},
          trun: [%Box.Trun{}]
        }

        {id, traf}
      end)

    {moof, mdat, parts_duration, part_duration_s} =
      Enum.reduce(parts, {moof, mdat, state.part_duration, 0}, fn {track_id, samples},
                                                                  {moof, mdat, parts_duration,
                                                                   part_duration} ->
        traf =
          samples
          |> Enum.reduce(trafs[track_id], &Box.Traf.store_sample(&2, &1))
          |> Box.Traf.finalize(true)

        traf_dur = Box.Traf.duration(traf)
        part_duration_s = traf_dur / state.tracks[track_id].timescale
        parts_duration = Map.update!(parts_duration, track_id, &(&1 + traf_dur))

        moof = %{moof | traf: [traf | moof.traf]}
        mdat = %{mdat | content: [Enum.map(samples, & &1.payload) | mdat.content]}
        {moof, mdat, parts_duration, max(part_duration, part_duration_s)}
      end)

    moof = %{moof | traf: Enum.reverse(moof.traf)}
    mdat = %{mdat | content: Enum.reverse(mdat.content)}

    moof = Box.Moof.update_base_offsets(moof, Box.size(moof) + @mdat_header_size, true)
    fragment = Box.serialize([moof, mdat])

    {fragment, part_duration_s,
     %{state | part_duration: parts_duration, fragments: [fragment | state.fragments]}}
  end

  @impl true
  def flush_segment(%{fragments: []} = state) do
    {moof, mdat} = build_moof_and_mdat(state)

    base_data_offset = Box.size(moof) + @mdat_header_size

    moof = Box.Moof.update_base_offsets(moof, base_data_offset, true)

    tracks =
      Enum.reduce(moof.traf, state.tracks, fn traf, tracks ->
        Map.update!(
          tracks,
          traf.tfhd.track_id,
          &%{&1 | duration: &1.duration + Box.Traf.duration(traf)}
        )
      end)

    segment_data = Box.serialize([moof, mdat])
    state = %{state | tracks: tracks, current_fragments: new_fragments(tracks)}

    {segment_data, state}
  end

  def flush_segment(%{fragments: fragments} = state) do
    {Enum.reverse(fragments), %{state | fragments: []}}
  end

  defp build_header(tracks) do
    %Box.Moov{
      mvhd: %Box.Mvhd{
        creation_time: DateTime.utc_now(),
        modification_time: DateTime.utc_now(),
        next_track_id: length(tracks) + 1
      },
      trak: Enum.map(tracks, &Track.to_trak(&1, ExMP4.movie_timescale())),
      mvex: %Box.Mvex{
        trex: Enum.map(tracks, & &1.trex)
      }
    }
  end

  defp new_fragments(tracks) do
    Map.new(tracks, fn {id, track} ->
      traf = %Box.Traf{
        tfhd: %Box.Tfhd{track_id: id},
        tfdt: %Box.Tfdt{base_media_decode_time: track.duration},
        trun: [%Box.Trun{}]
      }

      {id, {traf, []}}
    end)
  end

  defp build_moof_and_mdat(state) do
    moof = %Box.Moof{mfhd: %Box.Mfhd{sequence_number: 0}}
    mdat = %Box.Mdat{content: []}

    {moof, mdat} =
      Enum.reduce(state.current_fragments, {moof, mdat}, fn {_track_id, {traf, data}},
                                                            {moof, mdat} ->
        traf = Box.Traf.finalize(traf, true)
        data = Enum.reverse(data)

        moof = %{moof | traf: [traf | moof.traf]}
        mdat = %{mdat | content: [data | mdat.content]}

        {moof, mdat}
      end)

    moof = %{moof | traf: Enum.reverse(moof.traf)}
    mdat = %{mdat | content: Enum.reverse(mdat.content)}

    {moof, mdat}
  end
end
