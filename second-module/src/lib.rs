use spacetimedb::{
    rand::{seq::SliceRandom, Rng},
    reducer, table, ConnectionId, Identity, ReducerContext, Table, Timestamp,
};

#[table(name = hello_world, public)]
pub struct HelloWorld {
    #[primary_key]
    #[auto_inc]
    something: u8,
}

#[reducer(init)]
pub fn move_user(ctx: &ReducerContext) -> Result<(), String> {
    ctx.db.hello_world().insert(HelloWorld { something: 0 });
    Ok(())
}
