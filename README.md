# anyspec

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI](https://github.com/koduki/anyspec/actions/workflows/ci.yml/badge.svg)](https://github.com/koduki/anyspec/actions/workflows/ci.yml)

**anyspec** は Oracle Cloud Infrastructure (OCI) の設定値を期待値と比較する軽量なチェッカーツールです。IaC ツールではなく、セキュリティ・ガードレール設定など意図的にIaCから外しているクラウドのパラメータに対して、設定値のコード化及び意図しない変更を受けていないかを検知するために設計されています。このチェックツールで使われる期待値や出力されるレポートは「動く設計書」としての役割を持ちます。

## コンセプト

### anyspec は IaC ではない

anyspec は Terraform や CloudFormation のような Infrastructure as Code (IaC) ツールとは異なります。IaC ツールはインフラを定義・構築・変更するものですが、anyspec は**既存の設定を検証**するツールです。

多くの組織では、セキュリティ設定やガードレールなど、意図的に IaC の管理対象外としている設定があります。これらは:
- セキュリティチームが直接管理したい
- 誤って IaC で上書きされることを防ぎたい
- Terraform state とは別のライフサイクルで管理したい

anyspec はこれらの設定に対して:
1. **期待値をコード化**: YAML ファイルで「あるべき姿」を定義
2. **ドリフト検知**: 実際の設定と期待値を比較し、意図しない変更を検出
3. **設計書として記録**: チェック結果が設計意図の証跡となる

### 動く設計書としての GitHub Actions

anyspec のスペック YAML と出力レポートは「動く設計書」として機能します:
- **スペック YAML**: 設計意図を人間が読める形式で記述
- **チェック結果**: 設計通りかどうかを自動検証
- **GitHub Actions 統合**: PR でレビュー、Job Summary で結果を確認、定期実行で継続監視

これにより、設計書が「ただのドキュメント」ではなく、常に検証・更新される生きたものになります。

## 特徴

- **YAML ベースの期待値定義**: 人間が読みやすい形式で設定の期待値を管理
- **動く設計書**: スペック YAML とチェック結果レポートが設計意図を文書化
- **Git 管理可能**: 変更履歴を PR でレビュー・追跡
- **複数の出力形式**: 人間向け Markdown と機械処理用 JSON の両方を出力
- **拡張可能なアダプター**: 新しいリソースタイプを容易に追加可能
- **環境変数のサポート**: `${VAR}` 形式で機密情報を外部化
- **CI/CD 対応**: 終了コードで pass/fail/error を区別し、定期実行や PR チェックに対応
- **GitHub Actions 統合**: Job Summary、ファイルアノテーション、GITHUB_OUTPUT への自動出力
- **オフライン検証**: `validate` コマンドで OCI 接続なしにスペックを検証
- **比較演算子**: `$gte`, `$lte`, `$in` などで柔軟な期待値を定義
- **一時的なウェイバー**: `until:` で期限付きの例外を設定 (レポートで明示)
- **複数の認証方式**: API キー、インスタンスプリンシパル、リソースプリンシパルに対応
- **クロスプラットフォーム**: Linux、macOS、Windows で動作

## アーキテクチャ

### 配布モデル

anyspec は2つの形態で利用できます:

1. **CRuby (開発・ローカル用)**: 標準の Ruby 環境で `bundle exec` 経由で実行
2. **Spinel バイナリ (配布用)**: [Spinel](https://github.com/matz/spinel) でコンパイルした単一バイナリ

Spinel バイナリは Windows を含むクロスプラットフォーム配布を想定していますが、開発自体は CRuby を使い続けます。ローカル開発やテストは CRuby で行い、配布用バイナリだけ Spinel でビルドするワークフローです。

### 実行時依存

anyspec バイナリは `oci` CLI を外部依存として呼び出します。`oci` CLI は anyspec に同梱**しません**—これは意図的なトレードオフです:
- `oci` CLI のバージョンを anyspec と独立して管理できる
- 組織で既に `oci` CLI がインストール・設定されている環境を想定
- CI では `oci` CLI のメジャーバージョンを固定することを推奨

### ビルトインアダプター

以下の5つのアダプタータイプがバイナリに組み込まれており、外部ファイルなしで動作します:
- `cloud_guard_configuration`: Cloud Guard の有効化状態
- `cloud_guard_target`: Cloud Guard ターゲットの設定
- `identity_authentication_policy`: パスワードポリシーなど認証設定
- `audit_configuration`: 監査ログの保持期間
- `object_storage_bucket`: Object Storage バケットの設定

これら以外のリソースタイプは、外部 YAML 定義で追加するか、Ruby で実装してリビルドします。

## インストール

### 開発環境 (CRuby)

ローカル開発やテストには CRuby を使用します:

```bash
git clone https://github.com/koduki/anyspec.git
cd anyspec
bundle install
```

実行:

```bash
bundle exec ruby -Ilib bin/anyspec check examples/oci-guardrails.yml
```

### 配布バイナリ (Spinel)

配布用の単一バイナリは Spinel でビルドします。詳細は [Spinel バイナリのビルド](#spinel-バイナリのビルド) を参照してください。

ビルド済みバイナリを使う場合:

```bash
./anyspec check examples/oci-guardrails.yml
```

**注意**: 実行環境には `oci` CLI が必要です。anyspec はバックエンドとして `oci` CLI を呼び出します。

## 使い方

### 基本的な実行

```bash
bin/anyspec check examples/oci-guardrails.yml
```

### オフライン検証 (validate)

OCI に接続せずにスペックファイルの構文とフィールドを検証します。

```bash
bin/anyspec validate examples/
```

validate コマンドは以下をチェックします:
- 必須フィールドの存在 (`id`, `title`, `cloud`, `type`, `expect`)
- 未知のアダプタータイプ
- 重複した ID
- 無効な `until` 日付形式
- 参照されている環境変数の設定有無

CI の早期チェックや PR レビュー前の検証に便利です。

### オプション

```bash
bin/anyspec check <spec.yml|directory> [options]
bin/anyspec validate <spec.yml|directory>

Options:
  --out-dir DIR       結果の出力先ディレクトリ (デフォルト: artifacts)
  --profile NAME      OCI 設定プロファイル名 (デフォルト: DEFAULT)
  --config PATH       OCI 設定ファイルのパス (デフォルト: ~/.oci/config)
  --auth-mode MODE    認証方式: config_file (デフォルト), instance_principal, resource_principal
  --oci-cli PATH      OCI CLI 実行ファイルのパス (デフォルト: oci, または OCI_CLI 環境変数)
  --adapters-dir DIR  外部アダプター定義ディレクトリ (複数はパス区切り文字で指定)
  --fail-on MODE      終了コードの制御 (下記参照)
  -h, --help          ヘルプを表示
  -v, --version       バージョンを表示

環境変数:
  OCI_CLI                  OCI CLI 実行ファイルのパス
  OCI_CLI_CONFIG_FILE      OCI 設定ファイルのパス
  OCI_AUTH_MODE            認証方式を上書き
  OCI_REGION               インスタンス/リソースプリンシパル認証時のリージョン
  ANYSPEC_ADAPTERS_DIR     外部アダプター定義ディレクトリ (--adapters-dir と同等)
```

### --fail-on オプション

終了コードの振る舞いを制御します:

| 値 | 動作 |
|---|---|
| (なし) | デフォルト: fail でも error でも非ゼロ終了 |
| `fail` | ドリフト検知時のみ非ゼロ (exit 1)。error のみの場合は exit 2 |
| `error` | 取得エラー時のみ非ゼロ (exit 2)。ドリフトのみは exit 0 |
| `never` | 常に exit 0 (レポートと出力は生成) |

```bash
# ドリフトを記録するが CI を止めない
bin/anyspec check specs/ --fail-on never

# 取得エラーは無視、ドリフトだけ CI を止める
bin/anyspec check specs/ --fail-on fail
```

### ディレクトリ指定

ディレクトリを指定すると、その配下の全ての `.yml` / `.yaml` ファイルを再帰的に読み込みます。

```bash
bin/anyspec check specs/
```

### クロスプラットフォーム対応

anyspec は Linux、macOS、Windows で動作します。

- **Linux/macOS**: `~/.oci/config` がデフォルトの設定ファイルパス
- **Windows**: `%USERPROFILE%\.oci\config` がデフォルトの設定ファイルパス

Ruby の `Dir.home` と `File.join` を使用しているため、OS に応じたパス解決が自動で行われます。

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

CI では Ubuntu、macOS、Windows の全プラットフォームでテストを実行しています。

## Spinel バイナリのビルド

開発・テストには CRuby を直接使用できます。配布用の Spinel バイナリをビルドする場合は以下の方法があります。

### Linux バイナリ (Docker)

Docker (Docker Desktop, Colima, OrbStack など) を使って Linux バイナリをビルドできます。Mac や Linux ホストから実行可能です。

```bash
# ヘルパースクリプトを使用
./scripts/build-linux-binary.sh

# または直接 Docker を使用
docker build --target extractor -t anyspec-builder .
docker run --rm -v $(pwd)/dist:/output anyspec-builder
```

ビルドされたバイナリは `dist/anyspec` に出力されます。

**プラットフォームの指定:**

```bash
# x86-64 (Intel/AMD) 向け
./scripts/build-linux-binary.sh --platform linux/amd64

# ARM64 (AWS Graviton など) 向け
./scripts/build-linux-binary.sh --platform linux/arm64
```

**重要**: この方法で生成されるのは **Linux バイナリ**です。macOS/Windows ネイティブバイナリではありません。

### macOS ネイティブバイナリ

macOS ネイティブバイナリが必要な場合は、Spinel を macOS に直接インストールしてビルドします:

```bash
# Spinel のビルドとインストール (初回のみ)
git clone https://github.com/matz/spinel.git
cd spinel
make deps && make
sudo make install

# anyspec ディレクトリに戻る
cd /path/to/anyspec

# ネイティブバイナリをビルド
spin build
```

ビルドされたバイナリは `build/bin/anyspec` に出力されます。

**依存関係**: Xcode Command Line Tools (`xcode-select --install`) が必要です。

### Windows ネイティブバイナリ (.exe)

Spinel は Windows ネイティブの `.exe` ビルドをサポートしています。MSYS2 または RubyInstaller Devkit が必要です。

#### 前提条件

以下のいずれかをインストール:
- **MSYS2** (推奨): https://www.msys2.org/
- **RubyInstaller with Devkit**: https://rubyinstaller.org/

MSYS2 UCRT64 シェルで必要なパッケージをインストール:

```bash
pacman -S --needed make diffutils curl tar git mingw-w64-ucrt-x86_64-gcc
pacman -S --needed mingw-w64-ucrt-x86_64-ruby  # MSYS2 のみ (Devkit は不要)
```

#### Spinel のビルド (初回のみ)

MSYS2 UCRT64 シェルで:

```bash
git clone https://github.com/matz/spinel.git
cd spinel
make deps && make

# PATH に追加
export PATH="$PWD/bin:$PATH"
```

#### anyspec のビルド

MSYS2 UCRT64 シェルで:

```bash
# SPINEL_SHELL を設定 (spin コマンドに必要)
export SPINEL_SHELL=/usr/bin/sh

# anyspec ディレクトリへ移動
cd /path/to/anyspec

# ビルド
spin build
```

または、ヘルパースクリプトを使用:

```bash
./scripts/build-windows-binary.sh
```

PowerShell から実行する場合:

```powershell
.\scripts\build-windows-binary.ps1
```

ビルドされたバイナリは `build/bin/anyspec.exe` (または `dist/anyspec.exe`) に出力されます。

#### Windows ビルドの注意事項

- **コミュニティメンテナンス**: Spinel の Windows サポートはコミュニティメンテナンスで、master より遅れる可能性があります ([参照](https://github.com/matz/spinel/blob/master/docs/windows.md))
- **クロスコンパイル不可**: Linux/macOS から Windows バイナリをクロスコンパイルすることはできません。Windows 上でビルドする必要があります
- **WSL 代替**: WSL (Windows Subsystem for Linux) を使用する場合は、Linux バイナリとしてビルドできます

### サポートするターゲットプラットフォーム

| プラットフォーム | ビルド方法 | 出力 | 備考 |
|-----------------|-----------|------|------|
| Linux x86-64 | Docker (linux/amd64) | `anyspec` | 最も一般的、サーバー向け |
| Linux ARM64 | Docker (linux/arm64) | `anyspec` | AWS Graviton, Raspberry Pi 64-bit |
| macOS Intel | macOS 上で直接ビルド | `anyspec` | Xcode CLT 必要 |
| macOS Apple Silicon | macOS 上で直接ビルド | `anyspec` | Xcode CLT 必要 |
| Windows x64 | Windows (MSYS2) で直接ビルド | `anyspec.exe` | MSYS2 UCRT64 必要 |
| Windows (WSL) | WSL 内で Docker または直接ビルド | `anyspec` (Linux) | WSL2 推奨 |

### 注意事項

- 生成されるバイナリは `oci` CLI を外部依存として呼び出します
- `oci` CLI はバイナリに同梱**されません**—実行環境に別途インストールが必要です
- CI 環境では `oci` CLI のメジャーバージョンを固定することを推奨します
- Windows では OCI CLI for Windows を使用: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm

## CI/CD での利用

### GitHub Actions

anyspec は GitHub Actions と深く統合されており、`GITHUB_ACTIONS=true` の場合に自動的に以下を行います:

- `$GITHUB_STEP_SUMMARY` に Markdown レポートを追記 (Job Summary として表示)
- `::error file=...` / `::notice file=...` ワークフローコマンドでファイルにアノテーション
- `$GITHUB_OUTPUT` に `pass`, `fail`, `error`, `exit_code` を出力
- JSON メタデータに CI コンテキスト (`github_sha`, `github_run_id`, `github_run_url` など) を含める

レポートには `intent`, `owner`, `note` が含まれ、ウェイバー中の項目は「設計上の例外」として明示されます。これにより、YAML スペックと出力レポートが「動く設計書」として機能します。

#### GitHub-hosted ランナーでの認証

**重要**: `ubuntu-latest`, `macos-latest`, `windows-latest` などの GitHub-hosted ランナーでは `--auth-mode instance_principal` は使用できません。インスタンスプリンシパルは OCI Compute インスタンス上でのみ動作します。

GitHub-hosted ランナーでは以下の方法を使用してください:

**方法 1: GitHub OIDC + OCI Workload Identity Federation (推奨)**

GitHub の OIDC トークンを OCI IAM で Resource Principal Session Token (RPST) に交換します。

1. OCI IAM で Workload Identity Federation を設定
   - issuer: `https://token.actions.githubusercontent.com`
   - 参照: [OCI JWT to RPST Workload Identity Federation](https://docs.oracle.com/en-us/iaas/Content/Identity/api-getstarted/token_exchange_grant_type_workload_id-federation.htm)

2. GitHub Actions ワークフローで OIDC トークンを取得し、OCI API で RPST に交換

3. `--auth-mode resource_principal` で anyspec を実行

```yaml
permissions:
  contents: read
  id-token: write  # OIDC トークン取得に必要
```

**方法 2: 設定ファイル + シークレット (フォールバック)**

GitHub Secrets から OCI 設定ファイルと秘密鍵を組み立てます。

```yaml
- name: Setup OCI config
  run: |
    mkdir -p $HOME/.oci
    echo "${{ secrets.OCI_CONFIG }}" > $HOME/.oci/config
    echo "${{ secrets.OCI_KEY }}" > $HOME/.oci/oci_api_key.pem
    chmod 600 $HOME/.oci/config $HOME/.oci/oci_api_key.pem
  shell: bash
```

**注意**: 秘密鍵をログに出力しないでください。`set -x` や `echo` での表示は避けてください。

#### 完全なワークフロー例

```yaml
name: OCI Guardrails Check
on:
  workflow_dispatch:
  schedule:
    - cron: '0 9 * * *'  # 毎日 9:00 UTC
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read
  # id-token: write  # OIDC を使う場合はコメント解除

jobs:
  check:
    runs-on: ubuntu-latest  # macos-latest, windows-latest でも動作
    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true

      - name: Setup OCI config
        run: |
          mkdir -p $HOME/.oci
          echo "${{ secrets.OCI_CONFIG }}" > $HOME/.oci/config
          echo "${{ secrets.OCI_KEY }}" > $HOME/.oci/oci_api_key.pem
          chmod 600 $HOME/.oci/config $HOME/.oci/oci_api_key.pem
        shell: bash

      - name: Run anyspec
        id: anyspec
        run: bundle exec ruby -Ilib bin/anyspec check specs/
        env:
          OCI_TENANCY_OCID: ${{ secrets.OCI_TENANCY_OCID }}
          OCI_NAMESPACE: ${{ secrets.OCI_NAMESPACE }}

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: anyspec-results
          path: artifacts/

      # GITHUB_OUTPUT を使った後続ステップの例
      - name: Check drift status
        if: always()
        run: |
          echo "Drift detected: ${{ steps.anyspec.outputs.fail }}"
          echo "Errors occurred: ${{ steps.anyspec.outputs.error }}"
```

### OCI セルフホストランナーでの認証

OCI Compute インスタンスや OKE で実行するセルフホストランナーでは、インスタンスプリンシパルまたはリソースプリンシパルが使用できます。

| 実行環境 | 認証方式 |
|---------|---------|
| OCI Compute インスタンス | `--auth-mode instance_principal` |
| OKE Pod (Workload Identity) | `--auth-mode resource_principal` |
| OCI Functions | `--auth-mode resource_principal` |

1. ダイナミックグループを作成し、インスタンスまたは OKE ワークロードを含める
2. 必要なリソースへの読み取り権限を付与するポリシーを作成
3. 適切な `--auth-mode` で実行

```bash
# crontab での例
0 * * * * cd /opt/anyspec && bin/anyspec check specs/ --auth-mode instance_principal
```

## アダプターの追加方法

anyspec は2つの方法でリソースタイプを追加できます:
1. **外部 YAML 定義**: バイナリ再ビルド不要、単純な get/list 操作向け
2. **Ruby アダプター**: 複雑なロジック向け、バイナリ再ビルドが必要

### 方法 1: 外部 YAML 定義 (推奨)

バイナリを再ビルドせずに新しいリソースタイプを追加できます。YAML ファイルで OCI CLI コマンドを定義するだけで、anyspec が自動的に認識します。

**重要**: 本番環境や CI では、アダプター定義をスペック YAML と同じリポジトリにバージョン管理し、`--adapters-dir` で読み込んでください。これにより、アダプター定義も「動く設計書」の一部として追跡できます。

```bash
# 推奨: バージョン管理されたアダプター定義
anyspec check specs/ --adapters-dir ./adapters

# または環境変数で指定
export ANYSPEC_ADAPTERS_DIR=./adapters
anyspec check specs/
```

#### 検索パス (上位が優先)

1. `--adapters-dir` / `ANYSPEC_ADAPTERS_DIR` (本番用、バージョン管理推奨)
2. 実行ファイルと同じディレクトリの `adapters/`
3. カレントディレクトリの `.anyspec/adapters/` (個人実験用)
4. ホームディレクトリの `~/.anyspec/adapters/` (個人実験用)

ホームディレクトリやカレントディレクトリのパスは個人的な実験用です。チームで共有する定義は必ず `--adapters-dir` で明示的に指定してください。

#### YAML 定義フォーマット

1ファイルに複数のアダプタータイプを定義できます。多数のファイルに分散させるより、1つのファイルにまとめることを推奨します:

```yaml
# adapters/adapters.yml
schema_version: "1.0"

adapters:
  - type: vcn_security_list
    locators:
      # 方法1: ID による直接取得
      - subcommand: network security-list get
        required_fields: [security_list_id]
        flag_mappings:
          security_list_id: --security-list-id
        extract_fields:
          - id
          - display_name
          - lifecycle_state

      # 方法2: 名前で検索
      - subcommand: network security-list list
        required_fields: [compartment_id, name]
        flag_mappings:
          compartment_id: --compartment-id
        static_flags:
          - { "--limit": "100" }
        list_filter_field: display-name
        list_filter_spec_field: name
        extract_fields:
          - id
          - display_name

  - type: network_security_group
    locators:
      - subcommand: network nsg get
        required_fields: [nsg_id]
        flag_mappings:
          nsg_id: --nsg-id
        extract_fields:
          - id
          - display_name
          - lifecycle_state
```

#### ビルトインアダプターのオーバーライド

同じタイプ名の外部定義は、ビルトインをオーバーライドします。実行時にログで通知されます:

```
Loaded external adapters from: ./adapters/adapters.yml
  Note: Built-in 'audit_configuration' overridden by ./adapters/adapters.yml
```

#### 外部アダプターの対応範囲

外部 YAML アダプターは単純な操作に適しています:

**対応可能:**
- 単一リソースの get (ID 指定)
- リストからの名前フィルタリング (simple list + filter)
- フラグマッピングによる OCI CLI 引数構築
- フィールド抽出

**Ruby アダプターが必要:**
- 複雑なネスト照合ロジック
- 複数リソースの組み合わせ (例: VCN + サブネット)
- カスタム JSON 処理
- 単純な list 以上の複雑なページネーション
- OCI 以外のクラウド

#### セキュリティ

外部 YAML 定義は `YAML.safe_load` で読み込まれます:
- 許可されるクラス: `Symbol` のみ (`Date`, `Time` は不許可)
- シェルインジェクションに繋がる可能性のあるパターン (`` `...` ``, `$(...)`) はブロックされます
- 各タイプは単一の `GenericCli` クラスで処理され、動的なクラス生成は行いません

#### レポート情報

実行レポート (JSON/Markdown) には以下の情報が含まれます:
- 読み込んだアダプター定義ファイル
- 外部定義されたタイプ一覧
- ビルトインアダプターのオーバーライド情報
- バージョン情報 (anyspec バージョン, アダプタースキーマバージョン, oci CLI バージョン)

詳細なサンプルは [`docs/adapter-examples/`](docs/adapter-examples/) を参照してください。

### 方法 2: Ruby アダプター (開発者向け、要リビルド)

複雑なロジックが必要な場合、OCI CLI を使用する Ruby アダプターを作成できます:

```ruby
# lib/anyspec/adapters/my_resource.rb
module Anyspec
  module Adapters
    class MyResource < Base
      ADAPTER_TYPE = 'my_resource'

      def fetch(spec)
        args = ['my-service', 'resource', 'get', '--resource-id', spec['resource_id']]
        data = run_oci_cli(args)
        normalized = normalize_oci_response(data)

        {
          'id' => normalized['id'],
          'name' => normalized['display_name'],
          'status' => normalized['lifecycle_state']
        }
      end
    end

    AdapterRegistry.register(MyResource::ADAPTER_TYPE, MyResource)
  end
end
```

1. `lib/anyspec.rb` に require を追加
2. テストを追加
3. Spinel で再ビルド

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
