# Characterization Test と三角測量の具体例

t-wada-tdd の「レガシーコード・仕様不明」開始点と「NEVER 仮実装を最終設計とみなす」の補足実例。

## Characterization Test

**目的**: 仕様が不明な既存コードの現在の振る舞いを、テストとして記録して固定する（マイケル・フェザーズの用語）。

**手順**:
1. 公開境界の関数・APIを選ぶ（利用者が触れる場所）。
2. 既知の入力で呼び、現在の戻り値をそのまま期待値としてテストに書く。
3. 実行して通ることを確認する。期待値を発明せず、現状を記録するだけなので、Red にならなくてよい。

**ルール**:
- 期待値を「あるべき姿」で推測しない。現状の出力をそのまま写す。
- 誤った振る舞いが判明したら、記録テストを仕様ベースの Red テストへ置き換えてから修正する。修正後も正しい記録テストは仕様の固定として残す。

**例**: レガシー関数 `calc_total(prices)`。

```python
# characterization: 現状を記録（期待値は実測値の写し。仮定を書かない）
def test_calc_total_records_current_behavior():
    assert calc_total([200, 300]) == 500   # 実測値
    assert calc_total([100])       == 100

# 仕様ベースの Red: 5%割引が仕様と判明した後
def test_calc_total_applies_discount():
    assert calc_total([200, 300]) == 475   # 現状は 500 なので失敗する
```

## 三角測量（Triangulation）

**目的**: 仮実装が通るだけのテストから、一般化を「失敗が要求した時点」でだけ実装を広げる。複数の異なる例で実装を絞る。

**手順**:
1. 最初の例で Red → 仮実装（定数・直書き）で Green。
2. 別の例を追加して Red にする。仮実装のまま通るなら、まだ一般化を要求していない。
3. 一般化が必要になった時点ではじめて、両方の例を通す実装を書く。

**例**: `fizz_buzz(n)`。

```python
def test_first_case():
    assert fizz_buzz(1) == "1"      # Red
# 仮実装: return "1" で Green

def test_second_case():
    assert fizz_buzz(2) == "2"      # Red → 仮実装が壊れる → ここで一般化
# 実装: return str(n) で両方 Green

def test_fizz_case():
    assert fizz_buzz(3) == "Fizz"   # Red → 分岐を追加
```

**ルール**:
- 仮実装は設計の一部とみなさない。通すための足場。
- 一度に複数の例を足さない。ひとつずつ、一般化が必要か確認する。