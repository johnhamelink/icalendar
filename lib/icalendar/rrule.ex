defmodule ICalendar.RRULE do
  @moduledoc """
  Serialize and deserialize RRULEs
  """

  alias ICalendar.Property
  alias ICalendar.Util.Deserialize

  @frequencies %{
    "SECONDLY" => :secondly,
    "MINUTELY" => :minutely,
    "HOURLY"   => :hourly,
    "DAILY"    => :daily,
    "WEEKLY"   => :weekly,
    "MONTHLY"  => :monthly,
    "YEARLY"   => :yearly
  }

  @days %{
    "SU" => :sunday,
    "MO" => :monday,
    "TU" => :tuesday,
    "WE" => :wednesday,
    "TH" => :thursday,
    "FR" => :friday,
    "SA" => :saturday
  }

  @months [:january, :february, :march,
           :april, :may, :june, :july,
           :august, :september, :october,
           :november, :december]


  @string_to_atom_keys %{
    "FREQ"       => :frequency,
    "COUNT"      => :count,
    "UNTIL"      => :until,
    "INTERVAL"   => :interval,
    "BYSECOND"   => :by_second,
    "BYMINUTE"   => :by_minute,
    "BYHOUR"     => :by_hour,
    "BYMONTHDAY" => :by_month_day,
    "BYYEARDAY"  => :by_year_day,
    "BYWEEKNO"   => :by_week_number,
    "BYSETPOS"   => :by_set_pos,
    "BYDAY"      => :by_day,
    "BYMONTH"    => :by_month,
    "WKST"       => :week_start,
    "X-NAME"     => :x_name
  }

  defstruct frequency: nil,
            until: nil,
            count: nil,
            interval: nil,
            by_second: [],
            by_minute: [],
            by_hour: [],
            by_day: [],
            by_month: [],
            by_month_day: [],
            by_year_day:  [],
            by_week_number: [],
            by_set_pos: [],
            week_start: nil,
            x_name: nil,
            errors: []

  @doc ~S"""
  Produces a list of months in the year
  """
  def months, do: @months

  @doc ~S"""
  Produce inverse of @string_to_atom_keys at compile time
  """
  defmacro _atom_to_string_keys do
    quote do: Deserialize.invert_map(@string_to_atom_keys)
  end

  @doc ~S"""
  Produce inverse of @frequencies at compile time
  """
  defmacro _inverted_frequencies do
    quote do: Deserialize.invert_map(@frequencies)
  end

  @doc ~S"""
  Produce inverse of @days at compile time
  """
  defmacro _inverted_days do
    quote do: Deserialize.invert_map(@days)
  end

  @doc ~S"""
  Produces a list of RRULE iCal String keys and their %ICalendar.RRULE{}
  counterparts.
  """
  def string_to_atom_keys, do: @string_to_atom_keys
  def string_to_atom_keys(:inverted), do: _atom_to_string_keys()


  @doc ~S"""
  Produces a list of valid RRULE frequencies and their %ICalendar.RRULE{}
  counterparts.
  """
  def frequencies, do: @frequencies
  def frequencies(:inverted), do: _inverted_frequencies()


  @doc ~S"""
  Produces a list of valid RRULE days and their %ICalendar.RRULE{}
  counterparts.
  """
  def days, do: @days
  def days(:inverted), do: _inverted_days()


  @doc ~S"""
  This function is used to determine whether an RRULE struct has errors or not

      iex> ICalendar.RRULE.valid(%ICalendar.RRULE{errors: []})
      true

      iex> ICalendar.RRULE.valid(%ICalendar.RRULE{errors: ["error"]})
      false
  """
  def valid(%ICalendar.RRULE{errors: []}), do: true
  def valid(%ICalendar.RRULE{errors: err}) when is_list(err), do: false

  @doc ~S"""
  This function is used to deserialize an RRULE string into a struct

  Sending an RRULE deserializes it:

      iex> "FREQ=DAILY;COUNT=10"
      ...> |> ICalendar.RRULE.deserialize
      {:ok,
        %ICalendar.RRULE{
          :frequency => :daily,
          :count     => 10
        }}

  Sending a bad RRULE produces an error:

      iex> "COUNT=1;UNTIL=20151224T083000"
      ...> |> ICalendar.RRULE.deserialize
      {:error, ["You can only set UNTIL or COUNT: not both at the same time"]}

  """
  def deserialize(rrule) when is_bitstring(rrule) do
    rrule
    |> String.split(";")
    |> Enum.map(fn (prop) ->
      [key, value] = String.split(prop, "=", parts: 2, trim: true)
      [key, params] = Deserialize.retrieve_params(key)

      %Property{key: String.upcase(key), value: value, params: params}
    end)
    |> Enum.map(&validate_param/1)
    |> Enum.reduce(%ICalendar.RRULE{}, &parse_attr/2)
    |> validate()
    |> respond()

  end

  def respond(rule = %ICalendar.RRULE{}) do
    if valid(rule) do
      {:ok, rule}
    else
      {:error, rule.errors}
    end
  end

  def validate(rule = %ICalendar.RRULE{}) do
    # If UNTIL and COUNT are both set, then it's an error
    if rule.until && rule.count do
      errors = [
        "You can only set UNTIL or COUNT: not both at the same time"
        | rule.errors]

      Map.put(rule, :errors, errors)
    else
      rule
    end
  end

  def parse_attr(%{key: key, value: value}, accumulator) do

    key =
      case Map.fetch(@string_to_atom_keys, key) do
        {:ok, atom} -> atom
        {:error} ->
            key
            |> String.downcase
            |> String.to_atom
      end

    Map.put(accumulator, key, value)
  end
  def parse_attr({:error, %Property{}, err_msg}, accumulator) do
    {:ok, errors} = Map.fetch(accumulator, :errors)
    Map.put(accumulator, :errors, [ err_msg | errors ])
  end

  @doc """
  This function is used to split up values into a list format. An operation is
  optionally passed to it to format each result in a certain way.

      iex> RRULE.parse_value_as_list("a,b,c")
      ["a", "b", "c"]

      iex> RRULE.parse_value_as_list("1,2,3", &(String.to_integer(&1)))
      [1,2,3]
  """
  def parse_value_as_list(value), do: parse_value_as_list(value, &(&1))
  def parse_value_as_list(value, operation) when is_function(operation) do
    vals =
      value
      |> String.split(",")

    vals
    |> is_bitstring
    |> case do
        true -> [vals]
        false -> vals
      end
    |> Enum.map(operation)
  end

  def validate_param(prop = %Property{key: "FREQ", value: value}) do
    case Map.fetch(@frequencies, value) do
      {:ok, freq}  -> %{prop | value: freq}
      :error -> {:error, prop, "'#{value}' is not an accepted frequency"}
    end
  end
  def validate_param(prop = %Property{key: "UNTIL", value: value}) do
    out = Deserialize.to_date(value, %{"TZID" => "Etc/UTC"})
    case out do
      {:ok, date} -> %{prop | value: date}
      _           -> {:error, prop, "'#{value}' is not a valid date"}
    end
  end
  def validate_param(prop = %Property{key: "COUNT", value: value}) do
    value = String.to_integer(value)
    case value >= 1 do
      true -> %{prop | value: value}
      false -> {:error, prop, "'COUNT' must be >= 1 if it is set"}
    end
  end
  def validate_param(prop = %Property{key: "INTERVAL", value: value}) do
    value = String.to_integer(value)
    case value >= 1 do
      true -> %{prop | value: value}
      false -> {:error, prop, "'INTERVAL' must be >= 1 if it is set"}
    end
  end
  def validate_param(prop = %Property{key: "BYSECOND", value: value}) do
    value =
      value
      |> parse_value_as_list(&(String.to_integer(&1)))

    validation =
      value
      |> Enum.map(&(&1 >= 0 && &1 <= 59))

    case false in validation do
      false -> %{prop | value: value}
      true -> {
        :error,
        prop,
        "'BYSECOND' must be between 0 and 59 if it is set"
      }
    end
  end
  def validate_param(prop = %Property{key: "BYMINUTE", value: value}) do
    value =
      value
      |> parse_value_as_list(&(String.to_integer(&1)))

    validation =
      value
      |> Enum.map(&(&1 >= 0 && &1 <= 59))

    case false in validation do
      false -> %{prop | value: value}
      true -> {
        :error,
        prop,
        "'BYMINUTE' must be between 0 and 59 if it is set"
      }
    end
  end
  def validate_param(prop = %Property{key: "BYHOUR", value: value}) do
    value =
      value
      |> parse_value_as_list(&(String.to_integer(&1)))

    validation =
      value
      |> Enum.map(&(&1 >= 0 && &1 <= 23))

    case false in validation do
      false -> %{prop | value: value}
      true -> {
        :error,
        prop,
        "'BYHOUR' must be between 0 and 23 if it is set"
      }
    end
  end
  def validate_param(prop = %Property{key: "BYMONTHDAY", value: value}) do
    value =
      value
      |> parse_value_as_list(&(String.to_integer(&1)))

    validation =
      value
      |> Enum.map(&((&1 >= 1 && &1 <= 31) || (&1 <= 1 && &1 >= -31 && &1 != 0)))

    case false in validation do
      false -> %{prop | value: value}
      true -> {
        :error,
        prop,
        "'BYMONTHDAY' must be between 1 and 31 or -1 and -31 if it is set"
      }
    end
  end
  def validate_param(prop = %Property{key: "BYYEARDAY", value: value}) do
    value =
      value
      |> parse_value_as_list(&(String.to_integer(&1)))

    validation =
      value
      |> Enum.map(&(
        (&1 >= 1 && &1 <= 366) || (&1 <= 1 && &1 >= -366 && &1 != 0)))

    case false in validation do
      false -> %{prop | value: value}
      true -> {
        :error,
        prop,
        "'BYYEARDAY' must be between 1 and 366 or -1 and -366 if it is set"
      }
    end
  end
  def validate_param(prop = %Property{key: "BYWEEKNO", value: value}) do
    value =
      value
      |> parse_value_as_list(&(String.to_integer(&1)))

    validation =
      value
      |> Enum.map(&((&1 >= 1 && &1 <= 53) || (&1 <= 1 && &1 >= -53 && &1 != 0)))

    case false in validation do
      false -> %{prop | value: value}
      true -> {
        :error,
        prop,
        "'BYWEEKNO' must be between 1 and 53 or -1 and -53 if it is set"
      }
    end
  end
  def validate_param(prop = %Property{key: "BYSETPOS", value: value}) do
    value =
      value
      |> parse_value_as_list(&(String.to_integer(&1)))

    validation =
      value
      |> Enum.map(&(
        (&1 >= 1 && &1 <= 366) || (&1 <= 1 && &1 >= -366 && &1 != 0)))

    case false in validation do
      false -> %{prop | value: value}
      true -> {
        :error,
        prop,
        "'BYSETPOS' must be between 1 and 366 or -1 and -366 if it is set"
      }
    end
  end
  def validate_param(prop = %Property{key: "BYDAY", value: value}) do
    # Upcase the values
    value =
      value
      |> parse_value_as_list(&(String.upcase(&1)))

    # Check to see if they're in the list of days
    validation =
      value
      |> Enum.map(&(&1 in Map.keys(@days)))

    # If they all are, then fetch the value for all of them and add them to the
    # property.
    case false in validation do
      false -> %{prop | value: Enum.map(value, &(Map.fetch!(@days, &1)))}
      true -> {
        :error,
        prop,
        "'BYDAY' must have a valid day string if set"
      }
    end
  end
  def validate_param(prop = %Property{key: "WKST", value: value}) do
    value = String.upcase(value)

    case Map.fetch(@days, value) do
      {:ok, day} -> %{prop | value: day}
      _ -> {
        :error,
        prop,
        "'WKST' must have a valid day string if set"
      }
    end
  end
  def validate_param(prop = %Property{key: "BYMONTH", value: value}) do
    value =
      value
      |> parse_value_as_list(
        &(String.to_integer(&1))
      )

    validation =
      value
      |> Enum.map(&(&1 >= 1 && &1 <= 12))

    case false in validation do
      false -> %{prop | value: Enum.map(value, &(Enum.at(@months, &1 - 1)))}
      true -> {
        :error,
        prop,
        "'BYMONTH' must be between 1 and 12 if it is set"
      }
    end
  end
  def validate_param(prop = %Property{key: "X-NAME"}), do: prop
  def validate_param(prop = %Property{key: key}) do
    {:error, prop, "'#{key}' is not a recognised property"}
  end
end
