# anyspec

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI](https://github.com/koduki/anyspec/actions/workflows/ci.yml/badge.svg)](https://github.com/koduki/anyspec/actions/workflows/ci.yml)

**anyspec** は Oracle Cloud Infrastructure (OCI) の設定値を期待値と比較する軽量なチェッカーツールです。IaC ツールではなく、セキュリティ・ガードレール設定など意図的にIaCから外しているクラウドのパラメータに対して、設定値のコード化及び意図しない変更を受けていないかを検知するために設計されています。このチェックツールで使われる期待値や出力されるレポートは「動く設計書」としての役割を持ちます。

## 特徴

- **YAML ベースの期待値定義**: 人間が読みやすい形式で設定の期待値を管理
- **Git 管理可能**: 変更履歴を PR でレビュー・追跡
- **複数の出力形式**: 人間向け Markdown と機械処理用 JSON の両方を出力
- **拡張可能なアダプター**: 新しいリソースタイプを容易に追加可能
- **環境変数のサポート**: `${VAR}` 形式で機密情報を外部化
- **CI/CD 対応**: 終了コードで pass/fail/error を区別し、定期実行や PR チェックに対応
- **比較演算子**: `$gte`, `$lte`, `$in` などで柔軟な期待値を定義
- **一時的なウェイバー**: `until:` で期限付きの例外を設定
- **複数の認証方式**: API キー、インスタンスプリンシパル、リソースプリンシパルに対応

## インストール

```bash
git clone https://github.com/koduki/anyspec.git
cd anyspec
bundle install
```

## 使い方

### 基本的な実行

```bash
bin/anyspec check examples/oci-guardrails.yml
```

### オプション

```bash
bin/anyspec check <spec.yml|directory> [options]

Options:
  --out-dir DIR       結果の出力先ディレクトリ (デフォルト: artifacts)
  --profile NAME      OCI 設定プロファイル名 (デフォルト: DEFAULT)
  --config PATH       OCI 設定ファイルのパス (デフォルト: ~/.oci/config)
  --auth-mode MODE    認証方式: config_file (デフォルト), instance_principal, resource_principal
  -h, --help          ヘルプを表示
  -v, --version       バージョンを表示

環境変数:
  OCI_AUTH_MODE       認証方式を上書き
  OCI_REGION          インスタンス/リソースプリンシパル認証時のリージョン
```

### ディレクトリ指定

ディレクトリを指定すると、その配下の全ての `.yml` / `.yaml` ファイルを再帰的に読み込みます。

```bash
bin/anyspec check specs/
```

## 終了コード

CI/CD での利用を考慮し、終了コードで結果を区別します。

| 終了コード | 意味 |
|-----------|------|
| `0` | 全てのチェックが `pass` |
| `1` | 少なくとも1件の `fail` (ドリフト検知) |
| `2` | `fail` なしだが、少なくとも1件の `error` (取得失敗) |

**重要**: `fail` は「取得成功したが期待値と不一致」、`error` は「取得自体に失敗（認証エラー、リソース未検出、API エラーなど）」を意味します。`fail` と `error` の両方が存在する場合、終了コードは `1` になります。

## スペック YAML 形式

### 基本構造

```yaml
- id: oci-cloud-guard-enabled          # 必須: 一意の識別子
  title: Cloud Guard が有効である        # 必須: チェック項目のタイトル
  intent: テナンシ全体の脅威検知を止められないようにする  # 任意: このチェックの意図・理由
  note: 無効化は原則禁止。例外は期間付きで note と PR に残す  # 任意: 運用上の備考
  owner: security                       # 任意: 担当者/チーム
  cloud: oci                            # 必須: クラウドプロバイダー
  type: cloud_guard_configuration       # 必須: アダプタータイプ
  compartment_id: ${OCI_TENANCY_OCID}   # タイプ固有: ロケーター
  expect:                               # 必須: 期待値（部分一致）
    status: ENABLED
```

### 環境変数の補間

`${ENV_VAR}` 形式で環境変数を参照できます。未設定の環境変数はエラーになります。

```yaml
compartment_id: ${OCI_TENANCY_OCID}
namespace: ${OCI_NAMESPACE}
```

### 比較演算子

厳密な一致だけでなく、比較演算子を使って柔軟な期待値を定義できます。

| 演算子 | 意味 | 例 |
|--------|------|-----|
| `$gte` | 以上 (>=) | `retention_period_days: { $gte: 365 }` |
| `$lte` | 以下 (<=) | `max_age: { $lte: 30 }` |
| `$gt` | より大きい (>) | `count: { $gt: 0 }` |
| `$lt` | より小さい (<) | `age: { $lt: 90 }` |
| `$in` | リストに含まれる | `status: { $in: [ENABLED, ACTIVE] }` |
| `$ne` | 等しくない (!=) | `status: { $ne: DISABLED }` |

複数の演算子を組み合わせて範囲チェックも可能です:

```yaml
- id: audit-retention-acceptable
  title: 監査ログ保持期間が1年以上3年以下
  cloud: oci
  type: audit_configuration
  compartment_id: ${OCI_TENANCY_OCID}
  expect:
    retention_period_days:
      $gte: 365
      $lte: 1095
```

**注意**: 型の比較は厳密です。`14` (整数) と `"14"` (文字列) は異なる値として扱われます。

### 一時的なウェイバー (until:)

一時的に期待値の不一致を許容する場合、`until:` フィールドで期限を設定できます。

```yaml
- id: cloud-guard-waived
  title: Cloud Guard (一時的に無効を許容)
  cloud: oci
  type: cloud_guard_configuration
  compartment_id: ${OCI_TENANCY_OCID}
  until: "2026-12-01"  # UTC でこの日付まで不一致を許容
  expect:
    status: ENABLED
```

- ウェイバー期間中は、不一致があっても `pass` として扱われます（ただしメッセージに記録）
- 期限を過ぎると通常通り `fail` になります
- 日付は UTC として解釈されます

## 対応アダプター

### cloud_guard_configuration

Cloud Guard の設定状態をチェックします。

**ロケーター:**
- `compartment_id` (必須): テナンシ OCID

**チェック可能なフィールド:**
- `status`: `ENABLED` | `DISABLED`
- `reporting_region`: レポーティングリージョン
- `self_manage_resources`: セルフマネージリソース設定

```yaml
- id: cloud-guard-enabled
  title: Cloud Guard が有効
  cloud: oci
  type: cloud_guard_configuration
  compartment_id: ${OCI_TENANCY_OCID}
  expect:
    status: ENABLED
```

### cloud_guard_target

Cloud Guard ターゲットの設定をチェックします。

**ロケーター:**
- `compartment_id` (必須): コンパートメント OCID
- `target_id` または `name`: ターゲットの識別子

**チェック可能なフィールド:**
- `display_name`: 表示名
- `lifecycle_state`: `ACTIVE` | `CREATING` | `DELETED` など
- `target_resource_type`: `COMPARTMENT` | `FACLOUD`
- `target_resource_id`: ターゲットリソース OCID

```yaml
- id: cloud-guard-target-active
  title: Cloud Guard ターゲットがアクティブ
  cloud: oci
  type: cloud_guard_target
  compartment_id: ${OCI_TENANCY_OCID}
  name: root-target
  expect:
    lifecycle_state: ACTIVE
```

### identity_authentication_policy

認証ポリシー（パスワードポリシー等）をチェックします。

**ロケーター:**
- `compartment_id` (必須): テナンシ OCID

**チェック可能なフィールド:**
- `password_policy.minimum_password_length`: 最小パスワード長
- `password_policy.is_uppercase_characters_required`: 大文字必須
- `password_policy.is_lowercase_characters_required`: 小文字必須
- `password_policy.is_numeric_characters_required`: 数字必須
- `password_policy.is_special_characters_required`: 特殊文字必須
- `password_policy.is_username_containment_allowed`: ユーザー名含有許可

```yaml
- id: password-policy-strong
  title: パスワードポリシーが強固
  cloud: oci
  type: identity_authentication_policy
  compartment_id: ${OCI_TENANCY_OCID}
  expect:
    password_policy:
      minimum_password_length:
        $gte: 14
      is_uppercase_characters_required: true
      is_lowercase_characters_required: true
      is_numeric_characters_required: true
      is_special_characters_required: true
```

### audit_configuration

監査ログの設定をチェックします。

**ロケーター:**
- `compartment_id` (必須): テナンシ OCID

**チェック可能なフィールド:**
- `retention_period_days`: ログ保持日数

```yaml
- id: audit-retention-365
  title: 監査ログ保持期間が365日以上
  cloud: oci
  type: audit_configuration
  compartment_id: ${OCI_TENANCY_OCID}
  expect:
    retention_period_days:
      $gte: 365
```

### object_storage_bucket

Object Storage バケットの設定をチェックします。

**ロケーター:**
- `namespace` (必須): ネームスペース
- `bucket_name` または `name` (必須): バケット名

**チェック可能なフィールド:**
- `public_access_type`: `NoPublicAccess` | `ObjectRead` | `ObjectReadWithoutList`
- `versioning`: `Enabled` | `Disabled` | `Suspended`
- `storage_tier`: `Standard` | `Archive`
- `is_read_only`: 読み取り専用フラグ
- `auto_tiering`: 自動階層化
- `object_events_enabled`: オブジェクトイベント有効
- `replication_enabled`: レプリケーション有効

```yaml
- id: bucket-private
  title: バケットが非公開
  cloud: oci
  type: object_storage_bucket
  namespace: ${OCI_NAMESPACE}
  bucket_name: sensitive-data
  expect:
    public_access_type: NoPublicAccess
    versioning: Enabled
```

## 出力形式

### 標準出力

チェック実行時、各チェックの結果を1行ずつ表示します。

```
=== Check Results ===
[PASS] cloud-guard-enabled (150ms)
[FAIL] audit-retention-365 (200ms) - retention_period_days: expected '365', got '90'
[ERROR] bucket-check (50ms) - Fetch error: BucketNotFound
```

### JSON (artifacts/result.json)

```json
{
  "metadata": {
    "tool": "anyspec",
    "version": "0.1.0",
    "run_id": "550e8400-e29b-41d4-a716-446655440000",
    "timestamp": "2026-01-15T10:30:00Z",
    "duration_ms": 1500,
    "profile": "DEFAULT",
    "region": "ap-tokyo-1",
    "auth_mode": "config_file",
    "spec_paths": ["/path/to/specs/guardrails.yml"],
    "summary": {
      "total": 3,
      "pass": 2,
      "fail": 1,
      "error": 0
    }
  },
  "results": [
    {
      "id": "oci-cloud-guard-enabled",
      "title": "Cloud Guard が有効である",
      "intent": "テナンシ全体の脅威検知を止められないようにする",
      "note": "無効化は原則禁止",
      "owner": "security",
      "status": "pass",
      "expected": { "status": "ENABLED" },
      "actual": { "status": "ENABLED" },
      "duration_ms": 150
    },
    {
      "id": "audit-retention",
      "title": "監査ログ保持期間",
      "owner": "compliance",
      "status": "fail",
      "expected": { "retention_period_days": { "$gte": 365 } },
      "actual": { "retention_period_days": 90 },
      "message": "retention_period_days: expected '{\"$gte\"=>365}', got '90'",
      "mismatches": [
        {
          "path": "retention_period_days",
          "expected": { "$gte": 365 },
          "actual": 90
        }
      ],
      "duration_ms": 200
    }
  ]
}
```

### Markdown (artifacts/result.md)

人間が読みやすい形式で結果を出力します。成功項目は簡潔に、失敗項目は期待値と実際の値を明示します。

## OCI 認証設定

### API キーファイル (デフォルト)

標準の OCI 設定ファイル (`~/.oci/config`) を使用します。

```ini
[DEFAULT]
user=ocid1.user.oc1..xxxxx
fingerprint=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..xxxxx
region=ap-tokyo-1
key_file=~/.oci/oci_api_key.pem
```

複数のプロファイルを使い分ける場合:

```bash
bin/anyspec check specs/ --profile PRODUCTION
```

### インスタンスプリンシパル

OCI Compute インスタンス上で、インスタンスに付与されたダイナミックグループの権限で実行します。API キーの管理が不要になります。

```bash
bin/anyspec check specs/ --auth-mode instance_principal
```

または環境変数で指定:

```bash
export OCI_AUTH_MODE=instance_principal
export OCI_REGION=ap-tokyo-1  # 必要に応じて
bin/anyspec check specs/
```

### リソースプリンシパル

OCI Functions や OKE ワークロードアイデンティティで実行する場合に使用します。

```bash
bin/anyspec check specs/ --auth-mode resource_principal
```

必要な環境変数:
- `OCI_RESOURCE_PRINCIPAL_VERSION`
- `OCI_RESOURCE_PRINCIPAL_REGION`
- その他 OCI SDK が必要とする環境変数

## テストの実行

```bash
bundle exec rspec spec/anyspec
```

## CI/CD での利用

### GitHub Actions

```yaml
name: OCI Guardrails Check
on:
  schedule:
    - cron: '0 9 * * *'  # 毎日 9:00 UTC
  push:
    branches: [main]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true

      - name: Run anyspec
        run: bundle exec ruby -Ilib bin/anyspec check specs/
        env:
          OCI_AUTH_MODE: instance_principal  # または設定ファイルを使う場合は削除
          OCI_TENANCY_OCID: ${{ secrets.OCI_TENANCY_OCID }}
          OCI_NAMESPACE: ${{ secrets.OCI_NAMESPACE }}

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: anyspec-results
          path: artifacts/
```

### OCI での定期実行

OCI Compute インスタンスや OKE で定期実行する場合、インスタンスプリンシパルを使用すれば API キーの管理が不要です。

1. ダイナミックグループを作成し、インスタンスまたは OKE ワークロードを含める
2. 必要なリソースへの読み取り権限を付与するポリシーを作成
3. `--auth-mode instance_principal` または `--auth-mode resource_principal` で実行

```bash
# crontab での例
0 * * * * cd /opt/anyspec && bin/anyspec check specs/ --auth-mode instance_principal
```

## アダプターの追加方法

新しいリソースタイプをサポートするには:

1. `lib/anyspec/adapters/` に新しいアダプターを作成

```ruby
# lib/anyspec/adapters/my_resource.rb
module Anyspec
  module Adapters
    class MyResource < Base
      ADAPTER_TYPE = 'my_resource'

      def fetch(spec)
        # create_client ヘルパーを使用（インスタンスプリンシパル対応）
        client = create_client(OCI::SomeService::Client)
        response = client.get_resource(spec['resource_id'])
        
        {
          'field1' => response.data.field1,
          'field2' => response.data.field2
        }
      end
    end

    AdapterRegistry.register(MyResource::ADAPTER_TYPE, MyResource)
  end
end
```

2. `lib/anyspec.rb` に require を追加

3. テストを追加

## ユースケース

### 1. セキュリティガードレールの監視

Terraform などで管理していないセキュリティ設定が、手動で変更されていないかを定期的にチェック。

### 2. コンプライアンス検証

監査ログ保持期間やパスワードポリシーなど、コンプライアンス要件を満たしているかを確認。

### 3. CI/CD パイプラインでの検証

PR マージ前や定期実行で設定のドリフトを検知。

## なぜ anyspec か

- **ServerSpec/InSpec**: サーバー内部の検証に強いが、クラウド API 経由のチェックには追加設定が必要
- **Steampipe**: SQL ベースで柔軟だが、単純な期待値チェックには over-engineering
- **Terraform**: IaC ツールとして優秀だが、セキュリティチームが直接変更したくない設定もある

anyspec は「YAML で期待値を書いて、差分があれば検知する」というシンプルなアプローチを採用しています。

## ライセンス

MIT License - 詳細は [LICENSE](LICENSE) ファイルを参照してください。
