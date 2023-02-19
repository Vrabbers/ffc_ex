defmodule FfcEx.PrivDir do

  @spec path() :: Path.t()
  def path() do
    List.to_string(:code.priv_dir(:ffc_ex))
  end

  @spec file(Path.t()) :: binary
  def file(file) do
    Path.join(path(), file)
  end
end
