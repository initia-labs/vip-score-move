# VIP Score

## Entry Functions

All entry functions can only be executed by addresses that are in `ModuleStore.deployers`.

### `set_init_stage`

Set initial stage

```rust
public entry fun set_init_stage(deployer: &signer, stage: u64)
```

### `finalize_script`

Finalize stage. Once stage finalized, can't change score of that stage anymore.

```rust
public entry fun finalize_script(deployer: &signer, stage: u64)
```

### `update_score_script`

Update several scores.

```rust
public entry fun update_score_script(
    deployer: &signer,
    stage: u64,
    addrs: vector<address>,
    update_scores: vector<u64>
)
```

### `add_deployer_script`

Add new address to `ModuleStore.deployer`

```rust
public entry fun add_deployer_script(
    publisher: &signer, deployer: address
)
```

### `remove_deployer_script`

Remove address from `ModuleStore.deployer`

```rust
public entry fun remove_deployer_script(
    publisher: &signer, deployer: address
)
```

## Public Functions

All public functions can only be executed by addresses that are in `ModuleStore.deployers`.

### `increase_score`

Increase score.

```rust
public fun increase_score(
    deployer: &signer,
    account: address,
    stage: u64,
    amount: u64
)
```

### `decrease_score`

Decrease score.

```rust
public fun decrease_score(
    deployer: &signer,
    account: address,
    stage: u64,
    amount: u64
)
```

### `update_score`

Update score.

```rust
public fun update_score(
    deployer: &signer,
    account: address,
    stage: u64,
    amount: u64
)
```

## View Functions

### `get_score`

Get score of given address and stage

```rust
public fun get_score(account: address, stage: u64): u64
```

### `get_scores`

Get scores of given stage

```rust
public fun get_scores(
    // The stage number
    stage: u64,
    // Number of results to return (Max: 1000)
    limit: u16,
    // Pagination key. If None, start from the beginning.
    // If provided, return results after this key in descending order.
    // Use the last returned address to fetch the next page.
    start_after: Option<address>
): GetScoresResponse
```

Response type

```rust
struct GetScoresResponse {
    stage: u64,
    scores: vector<Score>
}
```

### `get_total_score`

Get stage info

```rust
public fun get_total_score(stage: u64): u64
```
