# DSL テストガイド

このドキュメントでは、DSL や OCI コマンドレットを追加・修正する際のテスト方法を説明します。

## テスト構成

```
spec/
├── fixtures/
│   └── oci/                    # OCI CLI レスポンスのフィクスチャ
│       ├── compartments.json
│       ├── domains.json
│       ├── policies_all.json
│       └── ...
├── support/
│   └── dsl_test_helper.rb      # テストヘルパー（MockExecutor、DSLResult）
└── anyspec/dsl/
    ├── lexer_spec.rb           # トークナイザのテスト
    ├── parser_spec.rb          # パーサーのテスト
    ├── interpreter_spec.rb     # 実行エンジンのテスト
    ├── builtins_spec.rb        # ジェネリック builtin のテスト
    ├── oci_builtins_spec.rb    # OCI コマンドレットのテスト
    ├── oci_collection_spec.rb  # OCI 収集メカニズムのユニットテスト
    └── collector_e2e_spec.rb   # コレクタスクリプトの E2E テスト
```

## テスト種類と追加先

### 1. DSL 構文テスト

**場所**: `spec/anyspec/dsl/lexer_spec.rb`, `spec/anyspec/dsl/parser_spec.rb`

新しい構文を追加する場合：

```ruby
# lexer_spec.rb
it 'tokenizes new syntax' do
  tokens = tokenize('new_syntax')
  expect(tokens.first.type).to eq(:NEW_SYNTAX)
end

# parser_spec.rb
it 'parses new syntax' do
  ast = parse('new_syntax arg1 arg2')
  expect(ast.statements.first).to be_a(AST::NewSyntax)
end
```

### 2. ジェネリック builtin テスト

**場所**: `spec/anyspec/dsl/builtins_spec.rb`

新しい builtin 関数を追加する場合：

```ruby
describe 'new_builtin' do
  it 'performs expected operation' do
    result = run(<<~DSL)
      $input = [1, 2, 3]
      new_builtin $input
    DSL
    expect(result).to eq([1, 2, 3])
  end
end
```

### 3. OCI コマンドレットテスト

**場所**: `spec/anyspec/dsl/oci_builtins_spec.rb`, `spec/anyspec/dsl/oci_collection_spec.rb`

新しい OCI コマンドレットを追加する場合：

```ruby
# oci_collection_spec.rb
describe 'new_oci_commandlet' do
  it 'calls OCI CLI with correct arguments' do
    mock_executor = MockExecutor.new(responses: {
      'identity-domains new-resource list' => load_fixture('new_resource_all')
    })
    # ...テスト
  end
end
```

### 4. E2E コレクタテスト

**場所**: `spec/anyspec/dsl/collector_e2e_spec.rb`

コレクタスクリプトの出力形状を検証：

```ruby
describe 'New collection' do
  it 'includes newCollection in output' do
    result = DSLTestHelper.run_collector_script(executor: mock_executor)
    collections = result['domains'].values.first['collections']
    expect(collections['newCollection']).to be_an(Array)
  end
end
```

## フィクスチャ追加方法

### 1. フィクスチャ形式

OCI CLI の実レスポンスに合わせた形式を使用：

**SCIM list (--all 使用時)**:
```json
{
  "data": {
    "resources": [...],
    "schemas": ["urn:ietf:params:scim:api:messages:2.0:ListResponse"]
  },
  "opc-total-items": "数値文字列"
}
```

**IAM list**:
```json
{
  "data": [...]
}
```

**raw-request**:
```json
{
  "data": "{\"Resources\":[...],\"totalResults\":N}",
  "headers": {"content-type": "application/json"},
  "status": "200 OK"
}
```

### 2. フィクスチャ追加手順

1. `spec/fixtures/oci/` に JSON ファイルを作成
2. 実データから匿名化（OCID、メール、URL などを置換）
3. `CollectorMockExecutor` にルーティングを追加

```ruby
# spec/support/dsl_test_helper.rb
def route_to_fixture(argv)
  cmd_str = argv.join(' ')
  
  if cmd_str.include?('identity-domains new-resource list')
    @fixtures[:new_resource] || DSLTestHelper.load_fixture('new_resource_all')
  # ...
  end
end
```

## テストヘルパー使用方法

### DSL コード実行

```ruby
result = DSLTestHelper.run_dsl(<<~DSL)
  $x = [1, 2, 3]
  filter $x 'gt' 1
DSL

expect(result.value).to eq([2, 3])
expect(result.warnings).to be_empty
```

### 環境変数付き実行

```ruby
result = DSLTestHelper.run_dsl(
  '$tenancy_id',
  env: { 'tenancy_id' => 'ocid1.tenancy.oc1..xxx' }
)
```

### カスタム MockExecutor

```ruby
executor = DSLTestHelper::CollectorMockExecutor.new(
  fixtures: { policies: custom_policies_fixture },
  custom_responses: {
    /special-endpoint/ => { 'data' => { 'resources' => [] } }
  }
)

result = DSLTestHelper.run_collector_script(executor: executor)
```

## 回帰テスト追加ガイド

### foreach スコープ問題

```ruby
it 'foreach does not persist outer variable assignments' do
  result = DSLTestHelper.run_dsl(<<~DSL)
    $result = {}
    foreach item in $items {
      $result = set_key $result $item.id $item.val  # 外側に残らない
    }
    $result
  DSL
  expect(result.value).to eq({})  # 空のまま
end

it 'use foreach return value pattern instead' do
  result = DSLTestHelper.run_dsl(<<~DSL)
    $pairs = foreach item in $items {
      { "id": $item.id, "val": $item.val }  # ペアを返す
    }
    pairs_to_map $pairs 'id' 'val'  # 外側でマップ構築
  DSL
  expect(result.value).not_to be_empty
end
```

### 配列リテラル vs インデックスアクセス

```ruby
it 'space distinguishes array literal from index' do
  # $arr [$item] → 配列リテラル引数
  # $arr[$item]  → インデックスアクセス
  result = DSLTestHelper.run_dsl(<<~DSL)
    $arr = [1, 2, 3]
    $item = 99
    concat $arr [$item]  # スペースあり → 配列リテラル
  DSL
  expect(result.value).to eq([1, 2, 3, 99])
end
```

### OCID のドット処理

```ruby
it 'set_key preserves dots in OCID keys' do
  result = DSLTestHelper.run_dsl(<<~DSL)
    $obj = {}
    set_key $obj 'ocid1.domain.oc1..xxx' { "name": "test" }
  DSL
  expect(result.value.keys).to eq(['ocid1.domain.oc1..xxx'])
end
```

## CI との統合

テストは実 OCI CLI を使用せずに実行可能：

```bash
# すべての DSL テストを実行
bundle exec rspec spec/anyspec/dsl/

# E2E テストのみ実行
bundle exec rspec spec/anyspec/dsl/collector_e2e_spec.rb

# 特定のテストを実行
bundle exec rspec spec/anyspec/dsl/collector_e2e_spec.rb -e "foreach scoping"
```

## 警告収集テスト

```ruby
it 'collects warnings from script execution' do
  result = DSLTestHelper.run_dsl(<<~DSL)
    warn 'Warning message'
    'done'
  DSL

  expect(result.warnings.length).to eq(1)
  expect(result.warnings[0][:message]).to eq('Warning message')
end
```

## よくある問題と解決

### Mock: no response for [...]

`CollectorMockExecutor` にルーティングを追加：

```ruby
# spec/support/dsl_test_helper.rb の route_to_fixture メソッドに追加
elsif cmd_str.include?('identity-domains new-resource list')
  @fixtures[:new_resource] || DSLTestHelper.load_fixture('new_resource_all')
```

### Count mismatch エラー

`opc-total-items` とリソース数が一致しない場合に発生。フィクスチャの `opc-total-items` を正しい値に更新。

### undefined method エラー

`DSLResult` ラッパーが原因の場合、`.value` でアンラップ：

```ruby
expect(result.value).to be_a(Hash)
```
