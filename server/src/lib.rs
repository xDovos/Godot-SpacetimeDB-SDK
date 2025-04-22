pub mod main_types;

use main_types::lobby::{assign_user_to_lobby, user_disconnected};
use main_types::vectors::{get_random_position, Vector2, Vector3};

use spacetimedb::{
    rand::{seq::SliceRandom, Rng},
    reducer, table, Identity, ReducerContext, Table, Timestamp,
};

const PLAYER_SPEED: f32 = 10.0;

#[table(name = user, public)]
pub struct User {
    #[primary_key]
    identity: Identity,
    online: bool,
    lobby_id: u64,
}

#[table(name = user_data, public)]
pub struct UserData {
    #[primary_key]
    identity: Identity,
    name: String,
    lobby_id: u64,
    last_position: Vector3,
    direction: Vector2,
    player_speed: f32,
    last_update: Timestamp,
}

#[reducer(client_connected)]
pub fn client_connected(ctx: &ReducerContext) {
    if let Some(user) = ctx.db.user().identity().find(ctx.sender) {
        if let Some(connection_id) = ctx.connection_id {
            log::info!("ConnectionID : {}", connection_id);
        }

        if user.lobby_id == 0 {
            assign_user_to_lobby(ctx, ctx.sender);
        }
    } else {
        let new_name = get_random_name(&ctx);
        let pos = get_random_position(&ctx);

        ctx.db.user().insert(User {
            identity: ctx.sender,
            online: true,
            lobby_id: 0,
        });

        ctx.db.user_data().insert(UserData {
            identity: ctx.sender,
            name: new_name.clone(),
            lobby_id: 0,
            last_position: pos,
            player_speed: PLAYER_SPEED,
            direction: Vector2 { x: 0.0, y: 0.0 },
            last_update: ctx.timestamp,
        });

        if let Some(connection_id) = ctx.connection_id {
            log::info!("ConnectionID : {}", connection_id);
        }

        log::info!("New user {} : online", new_name);

        assign_user_to_lobby(ctx, ctx.sender);
    }
}

#[reducer(client_disconnected)]
pub fn client_disconnected(ctx: &ReducerContext) {
    if let Some(user) = ctx.db.user().identity().find(ctx.sender) {
        let lobby_id = user.lobby_id.clone();

        ctx.db.user().identity().update(User {
            online: false,
            lobby_id: 0, //remove lobby id when disconnected
            ..user
        });

        if let Some(mut user_data) = ctx.db.user_data().identity().find(ctx.sender) {
            let name = user_data.name.clone();
            user_data.lobby_id = 0; //remove lobby id from user data when disconnected
            ctx.db.user_data().identity().update(user_data);
            log::info!(
                "Reset UserData lobby_id for disconnected user {:?}. User {} offline",
                ctx.sender,
                name
            );
        } else {
            // This branch should be unreachable
            log::warn!("UserData not found for disconnecting user {:?}", ctx.sender);
        }

        if lobby_id != 0 {
            //Decrease lobby players count from lobby table
            user_disconnected(&ctx, lobby_id);
        }
    } else {
        // This branch should be unreachable
        log::warn!(
            "Disconnect event for unknown user with identity {:?}",
            ctx.sender
        );
    }
}

pub fn get_random_name(ctx: &ReducerContext) -> String {
    let possible_names = ["Will", "Espresso", "Joker", "ChatGPT", "Gemini"];
    let mut rng = ctx.rng();
    if let Some(name) = possible_names.choose(&mut rng) {
        return String::from(*name);
    } else {
        return String::from("Popa");
    }
}

#[reducer]
pub fn move_user(ctx: &ReducerContext, new_input: Vector2) -> Result<(), String> {
    let current_time = ctx.timestamp;

    if let Some(user) = ctx.db.user_data().identity().find(ctx.sender) {
        // --- Calculate Time Delta ---
        let time_since_last_update = current_time
            .duration_since(user.last_update)
            .unwrap_or_default();
        let delta_s = time_since_last_update.as_secs_f32();

        // --- Calculate New Position ---
        let mut new_pos = user.last_position;

        let prev_dir_len_sq =
            user.direction.x * user.direction.x + user.direction.y * user.direction.y;
        if prev_dir_len_sq > 0.001 {
            new_pos.x += user.direction.x * PLAYER_SPEED * delta_s;
            new_pos.z += user.direction.y * PLAYER_SPEED * delta_s;
        }

        // --- Normalize New Direction ---
        let mut new_dir = new_input;
        let new_dir_len_sq = new_dir.x * new_dir.x + new_dir.y * new_dir.y;

        if new_dir_len_sq > 0.001 {
            let len = new_dir_len_sq.sqrt();
            new_dir.x /= len;
            new_dir.y /= len;
        } else {
            new_dir = Vector2::new(0.0, 0.0);
        }

        // --- Update User State ---
        ctx.db.user_data().identity().update(UserData {
            last_position: new_pos,
            direction: new_dir,
            player_speed: PLAYER_SPEED,
            last_update: current_time,
            ..user
        });

        Ok(())
    } else {
        Err(format!("User not found!"))
    }
}

#[spacetimedb::reducer(init)]
pub fn init(ctx: &ReducerContext) {
    //log::info!("Start Invoke");
}
