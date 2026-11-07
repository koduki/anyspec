# Anyspec DSL ビルトイン関数

## パス操作

### `get obj path`
オブジェクトから指定パスの値を取得します。パスが存在しない場合は `null` を返します。

```
$obj = { "a": { "b": 42 } }
get $obj "a.b"  # => 42
```

### `get_opt obj path default`
オブジェクトから値を取得し、存在しない場合はデフォルト値を返します。

```
get_opt $obj "missing" "default"  # => "default"
```

### `has obj path`
指定パスが存在するかを確認します。

```
has $obj "a.b"  # => true
```

### `is_empty value`
値が null、空配列、空文字列かを確認します。

### `is_null value`
値が null かを確認します。

### `is_array value`
値が配列かを確認します。

## 配列操作

### `filter arr field value`
配列をフィールド値でフィルタリングします。

```
filter $items "status" "active"
```

### `filter_not arr field value`
指定値を除外します。

### `filter_in arr field values`
フィールド値が指定配列に含まれる要素を選択します。

### `filter_contains arr field substring`
フィールド値が部分文字列を含む要素を選択します。

### `map arr field`
配列の各要素から指定フィールドを抽出します。

```
map $items "id"  # => [1, 2, 3]
```

### `flatten arr [depth]`
ネストされた配列を平坦化します。

### `unique arr`
重複を除去します。

### `unique_by arr field`
指定フィールドの値で重複を除去します。

### `sort arr`
配列をソートします（安定ソート）。

### `sort_by arr field`
指定フィールドでソートします。

### `first arr`
最初の要素を返します。

### `last arr`
最後の要素を返します。

### `count arr`
配列の長さを返します。

### `concat arr1 arr2 ...`
複数の配列を連結します。

### `compact arr`
null 値を除去します。

## 集合操作

### `index_by arr field`
配列からキーでインデックス化されたオブジェクトを作成します。キー重複はエラー。

```
index_by $items "id"  # => { "id1": {...}, "id2": {...} }
```

### `keys obj`
オブジェクトのキー配列を返します。

### `values obj`
オブジェクトの値配列を返します。

### `union arr1 arr2`
和集合を返します。

### `difference arr1 arr2`
差集合を返します（arr1 から arr2 の要素を除去）。

### `intersection arr1 arr2`
共通部分を返します。

### `contains arr value`
配列に値が含まれるかを確認します。

### `contains_any arr values`
配列に指定値のいずれかが含まれるかを確認します。

### `merge obj1 obj2`
2つのオブジェクトをマージします。キー競合はエラー。

### `merge_all arr_of_objects`
オブジェクトの配列をマージします。

## オブジェクト操作

### `sort_keys obj`
オブジェクトのキーをアルファベット順にソートします（再帰的）。

### `omit obj key1 key2 ...`
指定キーを除外した新しいオブジェクトを返します。

### `pick obj key1 key2 ...`
指定キーのみを含む新しいオブジェクトを返します。

### `set_at obj path value`
指定パスに値を設定した新しいオブジェクトを返します。パスはドットで分割されます。

```
set_at $obj "a.b.c" 42
```

### `set_key obj key value`
指定キーに値を設定した新しいオブジェクトを返します。キーはドットで分割されません。
OCIDのようにドットを含むキーを設定する場合に使用します。

```
# キーにドットが含まれていてもそのまま保持される
set_key $obj "ocid1.domain.oc1..xxx" $value
```

### `pairs_to_map arr key_field value_field`
`{key_field: k, value_field: v}` 形式のオブジェクト配列をマップに変換します。
foreach の結果からマップを構築する際に使用します。

```
# foreach の結果からマップを構築
$pairs = foreach item in $items {
  { "id": $item.id, "data": $item.value }
}
$map = pairs_to_map $pairs 'id' 'data'
```

### `build path value`
パスから動的にネストされたオブジェクトを構築します。

### `eq a b`
等値比較。

### `not_eq a b`
非等値比較。

## 文字列操作

### `json_decode str`
JSON文字列をパースします。失敗時はエラー。

### `json_encode obj`
オブジェクトをJSON文字列に変換します。

### `capture str pattern`
正規表現でキャプチャします。名前付きグループはハッシュ、無名グループは配列で返します。

```
capture "hello-123" '(?<word>[a-z]+)-(?<num>\d+)'
# => { "word": "hello", "num": "123" }
```

### `split str delimiter`
文字列を分割します。

### `join arr delimiter`
配列を結合します。

### `starts_with str prefix`
プレフィックス確認。

### `ends_with str suffix`
サフィックス確認。

### `replace str from to`
文字列置換。

### `uri_encode str`
URIエンコード。

### `scim_escape str`
SCIMフィルタ用エスケープ。

## ユーティリティ

### `warn message`
警告を出力します（エラーにはなりません）。

### `warnings`
現在までに収集された警告（メッセージと位置）の配列を返します。

### `assert condition message`
条件が false の場合エラーを発生させます。

### `if_then condition then_value else_value`
条件分岐。

```
if_then $is_admin "admin" "user"
```

### `default value default_value`
値が null の場合デフォルト値を返します。

### `typeof value`
値の型を文字列で返します：`null`, `boolean`, `number`, `string`, `array`, `object`

### `coalesce val1 val2 ...`
最初の非null値を返します。

### `error message`
エラーを発生させます。

### `identity`
パイプラインの入力をそのまま返します（`$_` と同等）。

## OCI 専用ビルトイン

### `oci_group_closure endpoint group_ids`
指定したグループと入れ子のグループをページ送りして収集し、`groups` と `user_ids` を返します。循環を検出し、未知のメンバー種別は警告します。

### `oci_list_compartments tenancy_ocid`
テナンシー配下の全コンパートメントを取得します。

### `oci_list_domains compartment_id`
コンパートメント内のドメインを取得します。

### `oci_domain_list endpoint resource_type [attributes]`
SCIMリソースの一覧を取得します（ページ送り対応）。

### `oci_domain_list_filtered endpoint resource_type filter [attributes]`
SCIMフィルタ付きでリソースを取得します。

### `oci_domain_get endpoint resource_type resource_id`
単一のSCIMリソースを取得します。

### `oci_domain_singleton endpoint resource_type`
シングルトンリソースを取得します（AuthenticationFactorSettings等）。

### `oci_raw_get endpoint path`
`/admin/v1/` 配下へのRaw GETリクエスト（ConditionGroups, SsoSettings用）。

### `oci_group_members endpoint group_id`
グループメンバーを属性ページ送りで取得します。

### `scim_filter field op value`
SCIMフィルタ文字列を構築します。

### `classify_attribute_value value`
attributeValue の形式を分類します：`json`, `iprange_ref`, `function_expr`, `string`, `null`

### `extract_iprange_refs value`
`#inIPRange("id")` 形式の参照を抽出します。

### `extract_condition_refs condition`
Condition からグループ/ユーザー参照を抽出します。

### `find_admin_roles app_roles`
adminRole が true のロールをフィルタします。

### `validate_sequence rules policy_name`
rules の sequence 重複を検出し、警告メッセージを返します。

### `check_ref_integrity refs lookup ref_type`
参照の整合性を検証し、欠落した参照の警告メッセージを返します。
