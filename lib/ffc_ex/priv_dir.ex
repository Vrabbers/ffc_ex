defmodule FfcEx.PrivDir do
  @spec path() :: Path.t()
  def path() do
    Application.app_dir(:ffc_ex, "priv")
  end

  @spec file(Path.t()) :: String.t()
  def file(file) do
    Path.join(path(), file)
  end
end
