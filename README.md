# Tus.Storage.S3

This was based forkked from an abandoned project on github from https://github.com/jpsca
it has been completely rewritten for 2026.

Amazon S3 (and S3-compatible) storage backend for the Elixir resumable file upload server.

## What It Provides

* **Direct Multipart Streaming:** Maps incoming Tus `PATCH` chunks directly to S3 Multipart Upload parts (`UploadPart`), avoiding local disk buffering on your application servers.
* **Automatic Part Validation:** Enforces S3's minimum part size requirement (5 MB by default) for intermediate chunks while allowing smaller final chunks.
* **Orphan Prevention:** Automatically aborts incomplete multipart uploads when a client cancels or deletes an in-progress upload (`DELETE`), preventing lingering storage fees.
* **S3-Compatible Provider Support:** Configurable host, scheme, port, region, and ACLs to support AWS S3, MinIO, DigitalOcean Spaces, Cloudflare R2, and LocalStack.

---

## Installation

Add `tus` and `tus_storage_s3` (along with `ex_aws_s3` and a JSON/XML parser required by ExAws) to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tus, "~> 0.1.3"},
    {:tus_storage_s3, github: "data-twister/tus-storage-s3"},
    {:ex_aws, "~> 2.5"},
    {:ex_aws_s3, "~> 2.5"},
    {:hackney, "~> 1.20"},
    {:sweet_xml, "~> 0.7"}
  ]
end
```

Run `mix deps.get` to install.

---

## Configuration

### 1. Configure ExAws Credentials

Add your AWS credentials (or S3-compatible keys) to `config/config.exs` or `config/runtime.exs`:

```elixir
config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: "us-east-1"
```

### 2. Required AWS IAM Permissions

Ensure the IAM user or role accessing the bucket has the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListMultipartUploadParts",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::your-bucket-name/*"
    }
  ]
}
```

### 3. Configure Your Tus Controller

Define a Tus controller in your application (e.g., `lib/my_app_web/controllers/upload_controller.ex`) and configure it to use `Tus.Storage.S3`:

```elixir
defmodule MyAppWeb.UploadController do
  use MyAppWeb, :controller
  use Tus.Controller

  # Optional: Trigger business logic once all chunks have been assembled in S3
  def on_complete(file) do
    # file.path contains the final S3 object key (e.g., "uploads/abc-123")
    IO.inspect(file, label: "Upload finished")
    :ok
  end
end
```

Then configure the controller options in `config/config.exs`:

```elixir
config :tus, MyAppWeb.UploadController,
  storage: Tus.Storage.S3,
  s3_bucket: "your-bucket-name",
  s3_prefix: "uploads",
  # Optional settings:
  s3_host: "://amazonaws.com",
  s3_region: "us-east-1",
  s3_acl: :private,
  s3_min_part_size: 5 * 1024 * 1024, # 5 MB (AWS S3 minimum)
  # Cache backend to track upload offsets and part ETags between requests:
  cache: Tus.Cache.Memory,
  max_size: 1024 * 1024 * 500 # 500 MB max upload size
```

#### Example: Local MinIO / S3-Compatible Setup

```elixir
config :tus, MyAppWeb.UploadController,
  storage: Tus.Storage.S3,
  s3_bucket: "local-uploads",
  s3_host: "localhost",
  s3_port: 9000,
  s3_scheme: "http://",
  s3_min_part_size: 5 * 1024 * 1024,
  cache: Tus.Cache.Memory
```

---

## Wiring Into Phoenix Router

Forward your upload endpoint to `MyAppWeb.UploadController` in `lib/my_app_web/router.ex`:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/files", MyAppWeb do
    options "/", UploadController, :options
    match :head, "/:uid", UploadController, :head
    post "/", UploadController, :post
    patch "/:uid", UploadController, :patch
    delete "/:uid", UploadController, :delete
  end
end
```

> **Note:** Ensure your client sends chunks at least as large as `s3_min_part_size` (5 MB for AWS S3) for every request except the final chunk. If a client sends an intermediate chunk smaller than `s3_min_part_size`, `Tus.Storage.S3.append/3` returns `:too_small`.

---

## Configuration Reference

| Option | Required | Default | Description |
| :--- | :--- | :--- | :--- |
| `storage` | Yes | — | Must be set to `Tus.Storage.S3`. |
| `s3_bucket` | Yes | — | Target S3 bucket name. |
| `s3_prefix` | No | `""` | Folder prefix prepended to generated file UIDs. |
| `s3_host` | No | `"://amazonaws.com"` | S3 endpoint hostname. |
| `s3_region` | No | ExAws default | AWS region override. |
| `s3_scheme` | No | `"https://"` | Protocol scheme (`"http://"` or `"https://"`). |
| `s3_port` | No | `443` / `80` | Custom port for local or self-hosted S3 servers. |
| `s3_acl` | No | `nil` | Canned S3 ACL (e.g., `:private`, `:public_read`). |
| `s3_min_part_size` | No | `5242880` (5 MB) | Minimum byte size for non-final upload chunks. |
