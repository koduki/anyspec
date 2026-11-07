# OCI Identity Domains 収集

## 概要

OCI Identity Domains のセキュリティ関連設定を収集し、JSON形式で出力します。

## 使用方法

```bash
export OCI_TENANCY_OCID="ocid1.tenancy.oc1..xxxx"
anyspec run scripts/oci_identity_domains.flow
```

出力は `artifacts/identity_domains.json` に保存されます。

## 出力形式

```json
{
  "domains": {
    "<DOMAIN_ID>": {
      "meta": {
        "id": "...",
        "name": "...",
        "url": "...",
        "compartment-id": "..."
      },
      "collections": {
        "policies": [...],
        "rules": [...],
        "conditions": [...],
        "networkPerimeters": [...],
        "conditionGroups": [...],
        "identityProviders": [...],
        "socialIdentityProviders": [...],
        "passwordPolicies": [...],
        "authenticationFactorSettings": [...],
        "kmsiSettings": [...],
        "ssoSettings": [...],
        "apps": [...],
        "adminAppRoles": [...],
        "adminGrants": [...],
        "targetGroups": [...],
        "targetUsers": [...]
      }
    }
  },
  "warnings": [...]
}
```

## 収集対象

### ドメイン探索

1. `oci iam compartment list` でテナンシー配下の全コンパートメントを取得
2. 各コンパートメントで `oci iam domain list` を実行
3. 全ドメインの属性を出力し、ACTIVE なドメインについて設定を収集

ACTIVE 以外のドメインも `domains` に残し、`collected: false` と `reason: "domain_not_active"` を出力します。未収集のドメインに空の設定を与えることはありません。

### ドメインごとの収集

| リソース | CLI/API | 備考 |
|---------|---------|------|
| Policies | `identity-domains policy list` | rules 属性を含む |
| Rules | `identity-domains rule list` | conditionGroup 参照 |
| Conditions | `identity-domains condition list` | attributeValue を分類 |
| NetworkPerimeters | `identity-domains network-perimeters list` | IPアドレス範囲 |
| ConditionGroups | `raw-request /admin/v1/ConditionGroups` | CLI未サポート |
| IdentityProviders | `identity-domains identity-providers list` | SAML等 |
| SocialIdentityProviders | `identity-domains social-identity-provider list` | Google等 |
| PasswordPolicies | `identity-domains password-policies list` | パスワード要件 |
| AuthenticationFactorSettings | `identity-domains authentication-factor-settings list` | MFA設定 |
| KmsiSettings | `identity-domains kmsi-settings list` | KMSI設定 |
| SsoSettings | `raw-request /admin/v1/SsoSettings` | SSO設定 |
| Apps | `identity-domains apps list` | ポリシー参照あり |

### 特権アクセス

- **AdminAppRoles**: `adminRole eq true` でフィルタ
- **Grants**: 各管理者ロールへの付与を取得
- **対象グループ**: 管理者Grant + Administrators + Condition参照
- **対象ユーザー**: 管理者Grant + グループメンバー + Condition参照

一般ユーザー/グループ全件は取得しません。

## 参照整合性チェック

以下の参照が欠落している場合、警告を出力します：

- Policy → Rule
- Rule → Condition/ConditionGroup
- App → Policy (appSignonPolicy, idpPolicy)
- Condition の `#inIPRange` → NetworkPerimeter
- Grant → AppRole, Grantee
- rules の sequence 重複

## ページ送り

### IAM API

`--all` フラグを使用。

### SCIM API

- startIndex/count によるページ送り
- count 上限 1000
- totalResults の変動検出
- ID重複検出
- 取得件数と totalResults の照合

### グループメンバー

`members[startIndex=1&count=1000]` 形式の属性内ページ送り。
グループ本体は default 属性で取得し、メンバーは最大 100,000 件まで別途取得します。上限超過や重複を検知した場合は収集をエラーにします。実 OCI でのページ送りの動作確認は別途必要です。

## 制約・注意事項

- `raw-request` は実環境で未検証（ConditionGroups, SsoSettings のみ対象）
- AuthenticationFactorSettings / KmsiSettings の list には `--start-index`/`--count`/`--filter` は使用不可
- SocialIdentityProvider list には `--attributes` は使用不可
- 404 は「設定なし」に自動変換しない
- シェルを介さず argv で直接実行（Open3.capture3）
