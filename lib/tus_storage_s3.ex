defmodule Tus.Storage.S3 do
  @moduledoc """
  S3 (or compatible) storage backend for the [Tus server](https://hex.pm)

  ## Installation

  The package can be installed by adding `tus_storage_s3` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [
      {:tus, "~> 0.1.1"},
      {:tus_storage_s3, "~> 0.1.0"},
    ]
  end
  ```

  ## Configuration

  - `storage`: Set it as `Tus.Storage.S3`
  - `s3_bucket`: The name of your bucket
  - `s3_host`: Optional. `"://amazonaws.com"` by default
  - `s3_prefix`: Optional. Prefix added to all files. Empty by default
  - `s3_min_part_size`: The minimum size of a single part (except the last). In Amazon S3 this is 5MB.
    For other, compatible services, you might want/need to change this restriction.

  In order to allow this backend to function properly, the user accessing the bucket must have at least the
  following AWS IAM policy permissions for the bucket and all of its subresources:

s3:AbortMultipartUpload
s3:DeleteObject
s3:GetObject
s3:ListMultipartUploadParts
s3:PutObject
Furthermore, this uses the ExAWS package, so you'll need to add valid AWS keys to its config.

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role]
  ```

This means it will try to resolve credentials in this order:
- a. Look for the AWS standard `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables
- b. Resolve credentials with IAM

Consult the [ExAWS documentation](https://hexdocs.pm) for more details.
"""

alias ExAws.S3

@default_host "://amazonaws.com"
@default_min_part_size 5 * 1024 * 1024

@doc """
Start a Multipart Upload and store its `upload_id`.
"""
def create(file, config) do
  bucket = bucket(config)
  path = file_path(config, file)

  bucket
  |> S3.initiate_multipart_upload(path)
  |> ExAws.request(host: host(config))
  |> case do
    {:ok, %{body: %{upload_id: upload_id}}} ->
      file =
        file
        |> Map.put(:upload_id, upload_id)
        |> Map.put(:parts, [])
        |> Map.put(:path, path)

      {:ok, file}

    {:error, reason} ->
      {:error, reason}
  end
end

@doc """
Add data to an already started Multipart Upload (identified by `file.upload_id`).
Amazon restricts the minimum size of a single part (except the last one) to at least 5MB.
If the data is smaller than that, this function returns `:too_small`.
That limit can be customized with the config option `s3_min_part_size`.
"""
def append(file, config, body) do
  min_size = min_part_size(config)
  body_size = byte_size(body)
  is_last_chunk? = file.offset + body_size >= file.size

  if body_size < min_size and not is_last_chunk? do
    :too_small
  else
    do_append(file, config, body)
  end
end

defp do_append(file, config, body) do
  bucket = bucket(config)
  path = file_path(config, file)
  part_number = length(file.parts) + 1

  bucket
  |> S3.upload_part(path, file.upload_id, part_number, body)
  |> ExAws.request(host: host(config))
  |> case do
    {:ok, %{headers: headers}} ->
      etag = get_etag(headers)
      parts = file.parts ++ [{part_number, etag}]
      {:ok, %{file | parts: parts}}

    {:error, reason} ->
      {:error, reason}
  end
end

@doc """
Finish a Multipart Upload.
"""
def complete_upload(file, config) do
  bucket = bucket(config)
  path = file_path(config, file)

  bucket
  |> S3.complete_multipart_upload(path, file.upload_id, file.parts)
  |> ExAws.request(host: host(config))
  |> case do
    {:ok, _res} -> {:ok, file}
    {:error, reason} -> {:error, reason}
  end
end

@doc """
Delete an uploaded object or abort an in-progress multipart upload.
"""
def delete(file, config) do
  bucket = bucket(config)
  path = file_path(config, file)
  request_opts = [host: host(config)]

  if Map.get(file, :upload_id) do
    bucket
    |> S3.abort_multipart_upload(path, file.upload_id)
    |> ExAws.request(request_opts)
  end

  bucket
  |> S3.delete_object(path)
  |> ExAws.request(request_opts)
  |> case do
    {:ok, _res} -> :ok
    {:error, reason} -> {:error, reason}
  end
end

defp file_path(config, file) do
  [
    config |> Map.get(:s3_prefix, "") |> String.trim("/"),
    file.uid
  ]
  |> Enum.join("/")
  |> String.trim("/")
end

defp host(config) do
  Map.get(config, :s3_host, @default_host)
end

defp bucket(config) do
  Map.fetch!(config, :s3_bucket)
end

defp min_part_size(config) do
  Map.get(config, :s3_min_part_size, @default_min_part_size)
end

defp get_etag(headers) do
  headers
  |> Enum.find_value(fn {k, v} ->
    if String.downcase(k) == "etag", do: v
  end)
end
end
