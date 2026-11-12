defmodule Tus.Storage.S3Test do
  use ExUnit.Case, async: true

  alias Tus.Storage.S3

  defmodule FakeClient do
    @behaviour Tus.Storage.S3.Client

    @impl true
    def request(%{http_method: :post, params: %{"uploads" => _}}, _opts) do
      {:ok, %{body: %{upload_id: "upload-999"}}}
    end

    def request(%{http_method: :put, path: "raw/missing-etag"}, _opts) do
      {:ok, %{headers: []}}
    end

    def request(%{http_method: :put}, _opts) do
      {:ok, %{headers: [{"ETag", "\"part-etag\""}]}}
    end

    def request(%{http_method: :post}, _opts) do
      {:ok, %{body: %{}}}
    end

    def request(%{http_method: :delete, params: %{"uploadId" => "already-completed"}}, _opts) do
      {:error, {:http_error, 404, %{body: "NoSuchUpload"}}}
    end

    def request(%{http_method: :delete}, _opts) do
      {:ok, %{body: ""}}
    end
  end

  setup do
    test_pid = self()
    handler_id = "tus-s3-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:tus, :storage, :s3, :request, :start],
        [:tus, :storage, :s3, :request, :stop]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    config = %{
      s3_bucket: "media-bucket",
      s3_prefix: "/raw/",
      s3_min_part_size: 10,
      s3_client: FakeClient
    }

    file = %{uid: "file-1", offset: 0, size: 25}
    {:ok, config: config, file: file}
  end

  describe "create/2" do
    test "initiates multipart upload and emits telemetry", %{config: config, file: file} do
      assert {:ok, updated} = S3.create(file, config)
      assert updated.upload_id == "upload-999"
      assert updated.parts == []
      assert updated.path == "raw/file-1"

      assert_received {:telemetry_event, [:tus, :storage, :s3, :request, :stop], %{duration: _},
                       %{operation: :create, bucket: "media-bucket", key: "raw/file-1", result: :ok}}
    end
  end

  describe "append/3" do
    test "returns :too_small for non-final chunks smaller than min_part_size", %{
      config: config,
      file: file
    } do
      file = Map.merge(file, %{upload_id: "upload-999", parts: []})
      assert :too_small = S3.append(file, config, "short")
    end

    test "uploads part and records part number and ETag", %{config: config, file: file} do
      file = Map.merge(file, %{upload_id: "upload-999", parts: []})
      assert {:ok, updated} = S3.append(file, config, "0123456789")
      assert updated.parts == [{1, "\"part-etag\""}]
    end

    test "allows chunks smaller than min_part_size when completing the upload", %{
      config: config,
      file: file
    } do
      file = Map.merge(file, %{upload_id: "upload-999", offset: 20, parts: [{1, "e1"}, {2, "e2"}]})
      assert {:ok, updated} = S3.append(file, config, "final")
      assert length(updated.parts) == 3
    end

    test "returns {:error, :missing_etag} if S3 response lacks an ETag header", %{config: config} do
      file = %{uid: "missing-etag", offset: 0, size: 10, upload_id: "upload-999", parts: []}
      assert {:error, :missing_etag} = S3.append(file, config, "0123456789")
    end
  end

  describe "complete_upload/2" do
    test "finalizes the multipart upload", %{config: config, file: file} do
      file = Map.merge(file, %{upload_id: "upload-999", parts: [{1, "\"part-etag\""}]})
      assert {:ok, ^file} = S3.complete_upload(file, config)
    end
  end

  describe "delete/2" do
    test "aborts in-progress upload and deletes the object", %{config: config, file: file} do
      file = Map.put(file, :upload_id, "upload-999")
      assert :ok = S3.delete(file, config)
    end

    test "ignores 404 NoSuchUpload when deleting an already-completed upload", %{
      config: config,
      file: file
    } do
      file = Map.put(file, :upload_id, "already-completed")
      assert :ok = S3.delete(file, config)
    end
  end
end
