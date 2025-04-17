use spacetimedb::{
    rand::{seq::SliceRandom, Rng},
    reducer, table, ConnectionId, Identity, ReducerContext, SpacetimeType, Table, Timestamp,
};

const PLAYER_SPEED: f32 = 10.0;
#[derive(SpacetimeType)]
pub struct Vector3 {
    x: f32,
    y: f32,
    z: f32,
}

#[derive(SpacetimeType)]
pub struct Vector2 {
    x: f32,
    y: f32,
}

#[table(name = user, public)]
pub struct User {
    #[primary_key]
    identity: Identity,
    name: String,
    online: bool,
    last_position: Vector3,
    direction: Vector2,
    last_update: Timestamp,
}

#[table(name = message, public)]
pub struct Message {
    #[primary_key]
    #[auto_inc]
    message_id: u64,
    sender: Identity,
    sent: Timestamp,
    text: String,
}

#[reducer]
/// Clients invoke this reducer to set their user names.
pub fn set_name(ctx: &ReducerContext, name: String) -> Result<(), String> {
    let new_name = validate_name(name)?;
    if let Some(user) = ctx.db.user().identity().find(ctx.sender) {
        ctx.db.user().identity().update(User {
            name: new_name,
            ..user
        });
        Ok(())
    } else {
        Err("Cannot set name for unknown user".to_string())
    }
}

/// Takes a name and checks if it's acceptable as a user's name.
fn validate_name(name: String) -> Result<String, String> {
    if name.is_empty() {
        Err("Names must not be empty".to_string())
    } else {
        Ok(name)
    }
}

#[reducer]
/// Clients invoke this reducer to send messages.
pub fn send_message(ctx: &ReducerContext, text: String) -> Result<(), String> {
    let text = validate_message(text)?;
    log::info!("{}", text);

    ctx.db.message().insert(Message {
        sender: ctx.sender,
        text,
        sent: ctx.timestamp,
        message_id: 0,
    });

    Ok(())
}

/// Takes a message's text and checks if it's acceptable to send.
fn validate_message(text: String) -> Result<String, String> {
    if text.is_empty() {
        Err("Messages must not be empty".to_string())
    } else {
        Ok(text)
    }
}

#[reducer(client_connected)]
// Called when a client connects to the SpacetimeDB
pub fn client_connected(ctx: &ReducerContext) {
    if let Some(user) = ctx.db.user().identity().find(ctx.sender) {
        let name = user.name.clone();
        ctx.db.user().identity().update(User {
            online: true,
            ..user
        });
        if let Some(connection_id) = ctx.connection_id {
            log::info!("ConnectionID : {}", connection_id);
        }

        log::info!("User {} : online", name);
    } else {
        let new_name = get_random_name(&ctx);
        let pos = get_random_position(&ctx);
        ctx.db.user().insert(User {
            name: new_name.clone(),
            identity: ctx.sender,
            online: true,
            last_position: Vector3 {
                x: 0.0,
                y: 0.0,
                z: 0.0,
            },
            direction: Vector2 { x: 0.0, y: 0.0 },
            last_update: ctx.timestamp,
        });
        if let Some(connection_id) = ctx.connection_id {
            log::info!("ConnectionID : {}", connection_id);
        }

        log::info!("User {} : online", new_name);
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

pub fn get_random_position(ctx: &ReducerContext) -> (f32, f32) {
    let x_pos = ctx.rng().gen_range(-10.0..10.0);
    let z_pos = ctx.rng().gen_range(-10.0..10.0);

    (x_pos, z_pos)
}
#[reducer]
pub fn move_user(ctx: &ReducerContext, new_input: Vector2) -> Result<(), String> {
    let current_time = ctx.timestamp;

    if let Some(user) = ctx.db.user().identity().find(ctx.sender) {
        // --- Calculate Time Delta ---
        // Time elapsed since the server last updated this user's state
        let time_since_last_update = current_time
            .duration_since(user.last_update)
            .unwrap_or_default();
        let delta_s = time_since_last_update.as_secs_f32();

        // --- Calculate New Position ---
        // Based on the *previous* direction stored on the server and the time delta.
        let mut new_pos = user.last_position;

        // Only move if the previous direction was non-zero
        let prev_dir_len_sq =
            user.direction.x * user.direction.x + user.direction.y * user.direction.y;
        if prev_dir_len_sq > 0.001 {
            new_pos.x += user.direction.x * PLAYER_SPEED * delta_s;
            new_pos.z += user.direction.y * PLAYER_SPEED * delta_s;
        }

        // --- Normalize New Direction ---
        // Normalize the direction received from the client.
        let mut new_dir_x = new_input.x;
        let mut new_dir_z = new_input.y;
        let new_dir_len_sq = new_dir_x * new_dir_x + new_dir_z * new_dir_z;

        if new_dir_len_sq > 0.001 {
            // If client intends to move
            let len = new_dir_len_sq.sqrt();
            new_dir_x /= len;
            new_dir_z /= len;
        } else {
            // Client intends to stop
            new_dir_x = 0.0;
            new_dir_z = 0.0;
        }

        // --- Update User State ---
        ctx.db.user().identity().update(User {
            last_position: new_pos,
            direction: new_input,
            last_update: current_time,
            ..user
        });

        Ok(())
    } else {
        Err(format!("User not found!"))
    }
}

#[reducer(client_disconnected)]
// Called when a client disconnects from SpacetimeDB
pub fn client_disconnected(ctx: &ReducerContext) {
    if let Some(user) = ctx.db.user().identity().find(ctx.sender) {
        let new_name = user.name.clone();
        ctx.db.user().identity().update(User {
            online: false,
            ..user
        });
        log::info!("User {} : offline", new_name);
    } else {
        // This branch should be unreachable,
        // as it doesn't make sense for a client to disconnect without connecting first.
        log::warn!(
            "Disconnect event for unknown user with identity {:?}",
            ctx.sender
        );
    }
}

#[spacetimedb::reducer(init)]
pub fn init(_ctx: &ReducerContext) {
    // Called when the module is initially published
}
