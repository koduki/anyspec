# OCI Identity Domains調査とDSL機能への対応

調査日: 2026-11-07。Oracle公式CLI/APIドキュメント、およびOracle公式oci-cli実装を確認した。実機レスポンスの取得は行っていない。

## APIから導いた要件

|公式仕様で確認したこと|必要な機能・実装判断|根拠|
|---|---|---|
|compartmentの全階層にはテナンシー指定とsubtree=true、accessLevel=ANYが必要|全階層をOCI CLIのraw-request経由で取得しルートを集合に追加。列挙した各compartmentを有限反復|[compartment list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/compartment/list.html)|
|domain listはcompartment指定。属性には状態・種別・URL等がある|ドメイン属性をそのまま保存し、発見したURLをSCIM接続先として登録|[domain list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/domain/list.html)、[一覧の説明](https://docs.oracle.com/en-us/iaas/Content/Identity/domains/to-view-identity-domains.htm)|
|raw-requestはdata/headers/statusを返す。HTTPエラーでもプロセス正常終了があり得る|終了コードとHTTP statusを独立に検査。GETだけをtransport内部で生成|[raw-request](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/raw-request.html)、[公式実装](https://github.com/oracle/oci-cli/blob/master/src/oci_cli/raw_request_cli.py)|
|SCIMリストはResources/totalResults/startIndex/itemsPerPage|総数不変、進行、実ページ長、重複ID、上限を検証。startIndexは実取得件数だけ進める|[Search AppRoles](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-approles-get.html)|
|Policies.rulesはreturned=request、sequenceが評価順|default属性とのunionでrulesを明示要求。sequence数値順ソートと重複警告|[Search Policies](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-policies-get.html)|
|Rule.conditionGroupはConditionまたはConditionGroup|型判別付き参照ルール。URI文字列を実行せずID対応表と照合|[Search Rules](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-rules-get.html)|
|ConditionGroup.conditionsもCondition/ConditionGroupを参照|全件indexを作って相互参照を照合。DSLのユーザー定義再帰は不要|[Search Condition Groups](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-conditiongroups-get.html)|
|Conditions.attributeValueは文字列で、JSON配列や式を格納できる|JSON展開、条件属性ごとのフィルタ、正規表現抽出。式自体は実行しない|[Search Conditions](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-conditions-get.html)、[Group/User/IP条件の公式例](https://docs.oracle.com/en-us/iaas/Content/Identity/api-getstarted/entapp-create-ent-app-authz-policy.htm)|
|AppRole.adminRoleが管理権限を示す|管理ロールだけをサーバ側filterで取得|[Get AppRole](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-approles-id-get.html)|
|Grant.entitlement.attributeValueがAppRole ID。granteeはUser/Group/App/DynamicResourceGroup|対象roleに限定したGrant検索、付与先の型別処理、対象外型の警告|[Search Grants](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-grants-get.html)|
|Groups.membersはreturned=request。User/Group/DynamicResourceGroupの型がある|members明示要求、訪問済みID集合、上限付きgroup探索、Userだけを個別取得|[Search Groups](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-groups-get.html)|
|AppsにはsignonPolicy/idpPolicy、identityProvidersはreturned=request|ポリシー参照を保存・照合。identityProvidersを明示要求。一般ユーザーの割り当て一覧は求めない|[Search Apps](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-apps-get.html)|
|AuthenticationFactorSettings/SsoSettingsはリスト形式だが通常リストのcount/filter/startIndexは掲載されていない|settingsコレクションには未サポートのページ引数を付けない。1応答で不完全ならエラー|[MFA](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-authenticationfactorsettings-get.html)、[SSO](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-ssosettings-get.html)|
|KMSIにも専用listコマンドがあり、設定リストの取得が可能|settings扱いで取得。IDが固定文字列の場合も文字列IDとしてindex可能|[KMSI CLI list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/identity-domains/kmsi-settings/list.html)、[固定IDのGET例](https://docs.oracle.com/en-us/iaas/Content/Identity/api-getstarted/usingauthenticateapis.htm)|
|残りの構成リソースもSCIMリスト|共通ページ処理とindex/normalizeを再利用|[PasswordPolicies](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-passwordpolicies-get.html)、[IdentityProviders](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-identityproviders-get.html)、[NetworkPerimeters](https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-networkperimeters-get.html)|

## IAMでもraw-requestを使う理由

[oci-cliのrender実装](https://github.com/oracle/oci-cli/blob/master/src/oci_cli/cli_util.py)は空リストを出力しない場合がある。通常の`oci iam compartment list --all`や`domain list --all`の空stdoutを「0件」として受け入れると、取得異常と区別できない。そのため付属DSLは`iam-list`から`oci raw-request GET`で`/20160918/compartments`と`/20160918/domains`を読み、HTTP 200、配列data、headersを検査する。空配列は正当な0件として受け入れるが、空stdoutは一貫してエラーにする。IAMのページトークン重複・ID重複・進行停止・上限も検査する。

接続先のリージョン/realmを推測しないため、`iam_endpoint`を明示入力にした。[APIエンドポイント一覧](https://docs.oracle.com/en-us/iaas/api/)から利用環境に対応するURLを選ぶ。

## 注意した仕様上の差

- CLIのstart-index説明には「ページ」と「1-based index」の表現が混在する。レスポンス側のSCIM定義に従い、開始位置は1から実取得件数ずつ進める。ページ番号として1ずつ増やさない。
- API一般論のattributeSets=allは採用しない。資格情報や巨大な関連一覧まで収集しないよう、defaultと必要なrequest属性だけを明示する。
- 公式Group/User条件の例では、userNameの説明が名前なのにレスポンス例がGUID状の文字列になっている。値の見た目でIDと断定せず、attributeName=user.userNameなら名前検索する。解決しなければ警告とする。
- DomainがACTIVEでない場合は属性収集と内部構成収集を分ける。内部構成を空であると判断しない。
- 参照404は削除競合等を示す警告にできるが、403やコレクション全体の404を成功に変換しない。
- 任意のカスタムGroovyや式から参照を完全に抽出することはAPIスキーマだけでは保証できない。既知形式とURI参照を扱い、未知条件は警告に残す。

## 採用しなかった方法

- シェルやjqを起動して変換する方式: 引用規則・外部依存・評価範囲が増えるため。
- すべてのCLIレスポンスをsnake_caseへ変換: SCIM URNキーやAPIの原本との対応を壊しやすいため。
- すべての配列を無条件にソート: 評価順などの意味を失うため。
- Users/Groups全件を取得してから絞る: 今回の対象外データまで取得するため。
- 失敗時の空オブジェクトへの置換: 設定不存在との誤判定になるため。
