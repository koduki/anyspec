# anyspec Adapter DSL v1

## 目的と構成

anyspec共通のデータ収集言語を追加する。Ruby製のパーサー・型付きJSON値の実行エンジン・汎用データ変換を、OCI固有のI/Oから分離する。既存のRuby/YAMLアダプタと比較エンジンは継続利用できる。既存Identity Domainsスナップショットの移行互換は今回の受け入れ対象に含めない。

- `lib/anyspec/dsl/parser.rb`: 位置情報付きトークン、AST。シェルやRubyのevalは使わない。
- `data.rb` / `runtime.rb`: データ変換、限定反復、出力、警告。
- `process_runner.rb`: OCIプロセスの寿命と出力を制限。
- `oci.rb`: 読み取りコマンド、SCIMページング、参照グループ探索。
- `adapters/identity-domains.anyspec`: 対象の選択、集合演算、参照検証、出力構築。収集方針はこのファイルでレビューできる。
- `adapters/identity-domains.yml`: type、スクリプト、入力宣言だけを持つ登録用マニフェスト。

### 設計判断

1. データはJSONの値であり、パイプはバイトストリームではない。文字列への暗黙の変換や単語分割はしない。
2. 条件分岐はフィルタで表す。反復は既に得られた有限配列の`for`のみ。関数定義、再帰、while、if、外部シェル、リダイレクト、コマンド置換はない。
3. ページングとグループグラフの探索は上限付きのI/O組み込みに閉じ込める。DSLに無制限ループを追加しない。
4. 取得中の失敗では部分スナップショットを公開しない。参照先の明示的404だけを警告に落とせる`scim-get?`と、構成上の警告を分離する。
5. 通常CLIのkebab-caseとAPIのcamelCaseを混ぜない。IAM/SCIMとも`oci raw-request --http-method GET`で取得し、原本のキー名を維持する。
6. 配列の意味を壊さないため、正規化の既定では配列順序を保持する。集合と分かっているパスだけを指定してソートし、Policyのrulesは数値sequence順にする。

## 実行方法

Ruby開発環境では`bundle install`を実行し、以下を利用する。CLIのグローバルオプションはコマンドより前に置く。

```sh
bundle exec ruby -Ilib bin/anyspec validate-dsl adapters/identity-domains.anyspec
```

`inputs.json`にはテナンシーOCIDと、対象リージョン/realmのIAMエンドポイントを設定する。エンドポイントは[Oracle公式一覧](https://docs.oracle.com/en-us/iaas/api/)から選ぶ。東京商用リージョンの例を以下に示す。OCI CLIの認証・プロファイル・リージョンは既存anyspec設定を利用する。

```json
{"tenancy_id":"ocid1.tenancy.oc1..example","iam_endpoint":"https://identity.ap-tokyo-1.oci.oraclecloud.com"}
```

```sh
bundle exec ruby -Ilib bin/anyspec --profile PRODUCTION collect adapters/identity-domains.anyspec inputs.json
```

`collect`は成功時に完全なJSONをstdoutへ、警告をstderrへ出力する。構文・取得エラー時にはJSONを出さずexit 2。呼び出し側でファイルに保存する場合は一時ファイルに出して、終了コード0を確認してから旧スナップショットを置き換える。警告の有無で失敗にしたい場合は`warnings`を検証する。

specから利用する例:

```yaml
- id: identity-domain-inventory
  title: Identity Domains収集
  cloud: oci
  type: identity_domains_snapshot
  tenancy_id: ${OCI_TENANCY_OCID}
  iam_endpoint: https://identity.ap-tokyo-1.oci.oraclecloud.com
  expect:
    schema_version: 1
    warning_count: 0
```

```sh
bundle exec ruby -Ilib bin/anyspec --adapters-dir ./adapters check path/to/spec.yml
```

注意: 既存anyspec比較器は配列を部分一致で比較するため、`expect: {warnings: []}`だけでは「警告ゼロ」を保証しない。警告ゼロを検証するには`warning_count: 0`を期待値に指定する。

外部マニフェストは従来と同じ探索順序・優先順位でロードされる。スクリプトはマニフェストのディレクトリ配下に限定し、realpathで範囲を検証する。DSLソースはロード時に構文と全コマンドの引数数を検証する。`validate-dsl`は変数の実行時型やOCI権限までは検証しない。

## 文法

```text
statement := NAME '=' pipeline NEWLINE
           | pipeline NEWLINE
           | 'for' NAME 'in' pipeline 'do' NEWLINE statement* 'end' NEWLINE
pipeline  := command argument* ('|' command argument*)*
argument  := JSON | single_quoted_literal | bare_word | '$'NAME('.'KEY)*
```

JSONオブジェクト/配列は複数行で書ける。`#`から行末まではコメント。JSONの二重引用符文字列と単一引用符文字列には変数補間をしない。変数は独立した引数として渡す。引用した`$(...)`等はただのデータで、非引用のシェル構文は拒否する。`$input`は読み取り専用。ループ変数は終了時に元に戻し、ループ内の他の変数代入は後続処理で再利用できる。

```text
items = value [{"id":"a","active":true},{"id":"b","active":false}]
active = value $items | where active true | index id
for id in value $active | keys do
  value $id | emit selected $id
end
```

パスは`foo.bar`、または`["literal.key","child"]`。キー名に`.`を含む場合は配列で指定する。`collect`と`decode-at`の`*`は配列要素またはオブジェクト値を辿る。`get`はキー欠落をエラーとし、`get?`はnullを返す。falseと0は欠落扱いしない。

## コマンド一覧

|分類|コマンド|意味|
|---|---|---|
|構築|`value V`, `array V...`, `object K V...`|型を保った値・配列・オブジェクト。objectのキー重複はエラー|
|抽出|`get PATH`, `get? PATH`, `pluck PATH`, `pluck? PATH`|単一値または配列各要素のパス取得|
|走査|`collect PATH`|ワイルドカード付きパスから値の配列を取得。存在しない任意キーは省略|
|配列|`flatten`, `compact`, `unique`|1段平坦化、null除去、値重複除去|
|選択|`where PATH V`, `where-in PATH LIST`, `where-not-in PATH LIST`|等値・包含・非包含|
|部分一致|`where-contains PATH PATTERN`|指定配列に部分一致する要素がある行を選択|
|対応表|`index PATH`, `keys`, `values`, `merge MAP`, `put KEY VALUE`|index/mergeのキー競合はエラー。putだけは明示的な置換|
|集合|`union LIST...`, `difference LIST`, `intersection LIST`|型付き値を比較する集合演算|
|JSON|`parse-json`, `decode-json`, `decode-field KEY`, `decode-at PATH`|厳格なJSON解析／埋め込みJSON展開。decodeはJSONらしい接頭辞を持つ文字列だけ解析、壊れたJSONはエラー|
|正規表現|`scan PATTERN`|文字列葉を走査し、最初のキャプチャまたは一致全体を重複なしで返す。時間制限付き|
|正規化|`normalize OPTIONS`|キーソート、指定キー除外、指定配列のみ安定ソート|
|出力|`emit SEGMENT...`|パイプ値を結果の指定階層へ格納。既存の最終キーへの上書きは拒否|
|警告|`context V`, `warn CODE MESSAGE`, `warn-empty CODE MESSAGE`|警告の文脈、無条件警告、空配列時警告|
|整合性|`warn-missing MAP LABEL`, `warn-duplicates PATH LABEL`|ID欠落・同一優先度の警告|
|参照|`references RULES`, `links COLLECTIONS EXCLUDED_KEYS`|宣言したパス／型から参照を構築、またはSCIM URI参照をデータとして抽出|
|参照利用|`reference-ids COLLECTION`, `check-references MAPS`|対象ID抽出、収集済み対応表との照合|
|IAM|`iam-list ENDPOINT RESOURCE PARAMS`|IAM compartments/domainsをHTTP status付きで取得しopc-next-pageを辿る|
|OCI|`oci ARGV`|許可されたIAM読み取りコマンドを引数配列で実行|
|SCIM|`scim-list ENDPOINT COLLECTION [FILTER]`|検証付き全ページ収集|
|SCIM個別|`scim-get ENDPOINT COLLECTION ID`, `scim-get? ...`|必須GET／404だけを警告にしてnullを返すGET|
|SCIM条件|`scim-eq ATTRIBUTE VALUE`, `scim-and FILTER...`|JSONエスケープしたSCIMフィルタの構築|
|グループ|`scim-groups ENDPOINT IDS`|指定IDからGroup型メンバーを上限・訪問済み集合付きで探索|

`normalize`の例:

```json
{"drop":["$ref","meta","dateAdded"],"arrays":{"**.rules":"sequence","**.schemas":"$","**.members":"value"}}
```

`arrays`のキーはパス、値はソートキー。`$`は正規化済みJSON値全体。`*`は1階層、先頭`**`は任意の祖先。指定外の配列は順序を保持する。JSON文字列に埋め込まれた配列は`decode-at`等で展開してから必要に応じてソートする。

## 安全性と失敗モデル

- OCI以外の実行ファイルはDSLから指定できない。実行ファイルはホスト側`Config`で設定する。
- `oci`で許すのはcompartment/domain等の明示的なlist操作とそのオプションだけ。追加CLIオプション、`--from-json`、書き込み操作は拒否する。
- `raw-request`をDSLに直接公開しない。SCIMはGET固定、コレクションはallowlist、SCIM接続先は実際のIAM ListDomainsで発見したHTTPS originだけ。IAM側は管理者が入力に明示したHTTPS originを使う。レスポンスの`$ref`をURLとして実行しない。
- 引数配列によるプロセス起動、stdin即時クローズ、stdoutとstderrの同時読み取り。既定は1コマンド60秒・両出力合計16MiB。超過時は子プロセスを終了する。
- 異常終了・空stdout・不正JSON・HTTP異常・ページ不整合は取得エラー。403を「データなし」として扱わない。
- ページ上限1000、1ページ要求100件、1コレクション10万リソース、グループ探索10万ID。スクリプト1MiB、JSON字句深度64、for深度32、実行ステップ100万、正規表現1秒。
- 成功・失敗キャッシュはRunnerの1回のrunに限定。アダプタtypeと宣言入力で分離。認証設定はRunnerに固定。次回runは再収集する。取得結果は呼び出し側にコピーを渡す。
- 同一ID数・総件数で属性が同時変更されたケースまでは検出できない。SCIM APIには複数リクエストをまたぐトランザクションスナップショットを仮定しない。
- DSLは任意Ruby実行を許さないが、信頼できない第三者の定義を無条件に安全にするOSサンドボックスではない。定義とOCI権限は管理対象とする。

## Identity Domains収集結果

```json
{
  "schema_version":1,
  "tenancy_id":"ocid1.tenancy...",
  "domains":{
    "ocid1.domain...":{
      "attributes":{"id":"ocid1.domain...","lifecycleState":"ACTIVE","url":"https://..."},
      "collected":true,
      "collections":{"Policies":{"policy-id":{"id":"policy-id"}},"Users":{},"Groups":{}}
    }
  },
  "warning_count":0,
  "warnings":[]
}
```

対象コレクションは依頼の15種。ConditionGroupsはすべて取得して対応表を構築するため、再帰参照先を言語上の再帰で取得する必要はない。Users/Groupsの無条件一覧はtransportでも禁止する。

- 全コンパートメント階層をIAM GETでANY指定して取得し、削除済みを除き、テナンシー自身を追加してdomainsを列挙する。
- ドメイン属性は状態にかかわらず残す。非ACTIVEは`collected:false`と警告を残し、空collectionsを捏造しない。ACTIVEの取得エラーは収集全体を失敗させる。
- 管理者AppRolesを`adminRole eq true`で選択し、各ロールIDに対応するGrantsだけを検索する。
- Grantの付与先、Administrators、ポリシー等の参照先からGroup/User IDを得る。GroupのGroup型メンバーを展開し、訪問済みIDで循環を止める。User型メンバーを個別取得する。
- 条件の`user.groups[*].value`は埋め込みJSONのGroup ID、`user.id`はUser ID、`user.userName`は名前フィルタで解決する。`#inIPRange("id")`は正規表現でNetworkPerimeter IDを抽出する。
- `$ref`付きの拡張属性も抽出するが、作成者・更新者の監査メタデータを辿って無関係なUsersを収集しない。
- DynamicResourceGroup等の対象外の型は警告を残す。未知の条件名は`UNINTERPRETED_CONDITION`。Groovy等の任意式や名前だけの非標準参照は実行・推測しない。形式を追加する場合は収集DSLのルールを拡張する。
- 警告にはdomain contextを付与し、順序を安定化する。警告の内容はスナップショットに含まれる。

## 検証と実環境での確認事項

テストには、公式スキーマに基づく合成レスポンスを使用する。実テナンシーのダンプではない。複数ページ、ルート/子コンパートメント、全対象コレクション、循環グループ、ID/名前参照、権限エラー、HTTP404、件数変動、重複ID、タイムアウト、出力上限、位置診断、正規化、500specでの成功/失敗キャッシュを検証する。

```sh
bundle exec rspec spec/anyspec
```

実OCI認証情報を使った接続試験とSpinelバイナリでの動作確認は別途必要。特に実環境のカスタム条件・Rule.returnの埋め込み形式、CLIバージョン、権限による属性可視性を確認する。権限不足でAPIが属性を黙って省略する場合、クライアントだけでその完全性を保証することはできない。

調査の根拠と各APIから導いた機能は[OCI調査ノート](oci-identity-domains-research.md)を参照。
