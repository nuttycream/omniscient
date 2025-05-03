use std::{error::Error, fs, io::BufReader, path::Path};

use rand::seq::IndexedRandom;
use rodio::{Decoder, OutputStream, Sink};

pub fn get_sounds(assets: &str) -> Vec<String> {
    let path = Path::new(assets);
    let mut sounds = Vec::new();

    let entries = match fs::read_dir(path) {
        Ok(entries) => entries,
        Err(_) => return sounds,
    };

    for entry in entries.filter_map(Result::ok) {
        let path = entry.path();
        let is_chicken_sound = path
            .extension()
            .is_some_and(|ext| ext == "ogg");

        if is_chicken_sound {
            sounds
                .push(path.to_string_lossy().into_owned());
        }
    }

    sounds
}

pub fn play_chicken(
    sounds: &[String],
) -> Result<(), Box<dyn Error>> {
    if sounds.is_empty() {
        return Err("no chicken sounds".into());
    }

    let mut rng = rand::rng();
    let sound_file = sounds
        .choose(&mut rng)
        .ok_or("cannot choose a rand sound")?;

    let (_stream, stream_handle) =
        OutputStream::try_default()?;
    let sink = Sink::try_new(&stream_handle)?;

    let file = BufReader::new(fs::File::open(sound_file)?);
    let source = Decoder::new(file)?;

    sink.append(source);

    sink.sleep_until_end();

    Ok(())
}
