# anyspec

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**anyspec** は Oracle Cloud Infrastructure (OCI) の設定値を期待値と比較する軽量なチェッカーツールです。IaC ツールではなく、セキュリティ・ガードレール設定が意図しない変更を受けていないかを検知するために設計されています。

## 特徴

- **YAML ベースの期待値定義**: 人間が読みやすい形式で設定の期待値を管理
- **Git 管理可能**: 変更履歴を PR でレビュー・追跡
- **複数の出力形式**: 人間向け Markdown と機械処理用 JSON の両方を出力
- **拡張可能なアダプター**: 新しいリソースタイプを容易に追加可能
- **環境変数のサポート**: `${VAR}` 形式で機密情報を外部化

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
  --out-dir DIR     結果の出力先ディレクトリ (デフォルト: artifacts)
  --profile NAME    OCI 設定プロファイル名 (デフォルト: DEFAULT)
  --config PATH     OCI 設定ファイルのパス (デフォルト: ~/.oci/config)
  -h, --help        ヘルプを表示
  -v, --version     バージョンを表示
```

### ディレクトリ指定

ディレクトリを指定すると、その配下の全ての `.yml` / `.yaml` ファイルを再帰的に読み込みます。

```bash
bin/anyspec check specs/
```

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
      minimum_password_length: 14
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
  title: 監査ログ保持期間が365日
  cloud: oci
  type: audit_configuration
  compartment_id: ${OCI_TENANCY_OCID}
  expect:
    retention_period_days: 365
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

### JSON (artifacts/result.json)

```json
{
  "metadata": {
    "tool": "anyspec",
    "version": "0.1.0",
    "timestamp": "2026-01-15T10:30:00Z",
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
      "status": "pass",
      "expected": { "status": "ENABLED" },
      "actual": { "status": "ENABLED" }
    }
  ]
}
```

### Markdown (artifacts/result.md)

人間が読みやすい形式で結果を出力します。成功項目は簡潔に、失敗項目は期待値と実際の値を明示します。

## ステータスの意味

| ステータス | 意味 |
|-----------|------|
| `pass` | 期待値と実際の値が一致 |
| `fail` | 取得成功したが期待値と不一致 |
| `error` | 取得に失敗（認証エラー、権限エラー、リソース未検出、API エラー） |

**重要**: `fail` と `error` は区別されます。`error` は取得自体が失敗したケースであり、設定値の問題ではありません。

## 終了コード

- `0`: 全てのチェックが `pass`
- `1`: `fail` または `error` が1件以上

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
        # OCI API を呼び出して結果を Hash で返す
        client = OCI::SomeService::Client.new(config: config.oci_client_config)
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

## OCI 認証設定

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

## テストの実行

```bash
bundle exec rspec
```

## ユースケース

### 1. セキュリティガードレールの監視

Terraform などで管理していないセキュリティ設定が、手動で変更されていないかを定期的にチェック。

### 2. コンプライアンス検証

監査ログ保持期間やパスワードポリシーなど、コンプライアンス要件を満たしているかを確認。

### 3. CI/CD パイプラインでの検証

PR マージ前や定期実行で設定のドリフトを検知。

```yaml
# GitHub Actions example
- name: Check OCI guardrails
  run: |
    bin/anyspec check specs/guardrails/
  env:
    OCI_TENANCY_OCID: ${{ secrets.OCI_TENANCY_OCID }}
```

## なぜ anyspec か

- **ServerSpec/InSpec**: サーバー内部の検証に強いが、クラウド API 経由のチェックには追加設定が必要
- **Steampipe**: SQL ベースで柔軟だが、単純な期待値チェックには over-engineering
- **Terraform**: IaC ツールとして優秀だが、セキュリティチームが直接変更したくない設定もある

anyspec は「YAML で期待値を書いて、差分があれば検知する」というシンプルなアプローチを採用しています。

## ライセンス

MIT License - 詳細は [LICENSE](LICENSE) ファイルを参照してください。
