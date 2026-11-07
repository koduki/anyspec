# Anyspec DSL 言語仕様

汎用の軽量DSLで、Bash風の構文とjq的なビルトインを持ち、OCI Identity Domains等の構成情報収集に使用できます。

## 基本構文

### コメント

```
# これはコメントです
```

### 変数

変数は `$` で始まります。

```
$name = "value"
$count = 42
$items = [1, 2, 3]
$obj = { "key": "value" }
```

### リテラル

```
# 文字列
'シングルクォート文字列'
"ダブルクォート文字列 $variable を含む"

# 数値
42
-3.14

# 真偽値
true
false

# null
null

# 配列
[1, 2, 3]
["a", "b", "c"]

# オブジェクト
{ "key": "value", "num": 42 }
```

### フィールドアクセス

```
$obj.field           # ドット記法
$obj["key-name"]     # ブラケット記法
$obj.nested.field    # ネストされたアクセス
```

ハイフンを含むキーはブラケット記法を使用するか、アンダースコアに変換してアクセスできます。

### パイプライン

コマンドの出力を次のコマンドへ渡します。

```
$arr | filter $_ "status" "active" | map $_ "id"
```

パイプラインでは、前のコマンドの出力が `$_` に設定されます。

### foreach ループ

有限集合の要素を反復処理します。

```
foreach item in $items {
  $item.id
}
```

各反復の最後の式の値が配列に収集されます。

### コマンド呼び出し

```
command_name arg1 arg2 --flag value
```

## 入れないもの

以下の機能は意図的に含まれていません：

- if/else 条件分岐（代わりに `if_then` ビルトインを使用）
- while ループ
- 汎用 for ループ
- ユーザー定義関数
- 再帰呼び出し
- シェル実行
- 文字列の eval

## エラーメッセージ

エラーメッセージには必ず `file:line:column` が含まれます。

```
<script>:10:5: Unknown command: invalid_command
```

## ファイル拡張子

DSLスクリプトは `.flow` 拡張子を使用します。

## 実行

```bash
anyspec run script.flow
```

環境変数 `OCI_TENANCY_OCID` でテナンシーOCIDを指定します。
