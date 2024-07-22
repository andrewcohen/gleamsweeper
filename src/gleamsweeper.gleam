import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import lustre
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import plinth/javascript/console
import prng/random

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "body", Nil)

  Nil
}

const board_size = 10

const max_bombs = 15

pub type Board =
  dict.Dict(Coord, Tile)

fn over_board_coords() {
  list.combination_pairs(list.range(1, board_size))
  |> list.append(list.zip(list.range(1, board_size), list.range(1, board_size)))
  |> list.map(fn(a) { Coord(a.0, a.1) })
}

fn fold_over_board(acc, cb) {
  list.range(1, board_size)
  |> list.fold(acc, fn(acc, y) {
    list.range(1, board_size)
    |> list.fold(acc, fn(acc, x) { cb(acc, x, y) })
  })
}

fn map_over_board(cb) {
  list.range(1, board_size)
  |> list.map(fn(y) {
    list.range(1, board_size)
    |> list.map(fn(x) { cb(x, y) })
  })
}

pub fn init(_flags) -> Model {
  let rand_coord = fn() {
    let p =
      random.random_sample(random.pair(
        random.int(1, board_size),
        random.int(1, board_size),
      ))
    Coord(p.0, p.1)
  }

  let board =
    dict.new()
    |> list.fold(over: list.range(1, max_bombs), with: fn(board, _) {
      dict.insert(board, rand_coord(), Tile(Unchecked, Bomb(detonated: False)))
    })
    |> fold_over_board(fn(acc, x, y) {
      let tile =
        dict.get(acc, Coord(x, y))
        |> result.unwrap(Tile(Unchecked, Empty(0)))

      case tile {
        Tile(_, Bomb(_)) -> acc
        Tile(_, Empty(_)) -> {
          let count = neighbor_bomb_count(acc, Coord(x, y))
          dict.insert(acc, Coord(x, y), Tile(Unchecked, Empty(count)))
        }
      }
    })

  Game(board: board, selected_tool: Poke, state: Playing)
}

pub fn neighbor_bomb_count(board: Board, coord: Coord) -> Int {
  let get_neighbor = fn(c) -> Int {
    dict.get(board, c)
    |> result.map(fn(n) {
      case n {
        Tile(_, Bomb(_)) -> 1
        _ -> 0
      }
    })
    |> result.unwrap(0)
  }

  list.fold(from: 0, over: neighbors(coord), with: fn(acc, c) {
    acc + get_neighbor(c)
  })
}

pub type Tool {
  Poke
  Flag
}

const all_tools = [Poke, Flag]

pub type Tile {
  Tile(status: TileStatus, contents: TileContents)
}

pub type TileStatus {
  Unchecked
  Flagged
  Checked
}

pub type TileContents {
  Empty(adjacent_bombs: Int)
  Bomb(detonated: Bool)
}

pub type Coord {
  Coord(x: Int, y: Int)
}

pub type Model {
  Game(board: Board, selected_tool: Tool, state: GameState)
}

pub type GameState {
  Playing
  GameOver(won: Bool)
}

pub type Msg {
  Noop
  SelectTile(coord: Coord)
  SelectTool(tool: Tool)
}

const tile_size = "44px"

pub fn view(model: Model) -> Element(Msg) {
  html.body(
    [
      attribute.class("m-4 flex flex-col gap-4 select-none"),
      event.on_keydown(fn(k) {
        case k {
          " " -> SelectTool(Flag)
          _ -> Noop
        }
      }),
      event.on_keyup(fn(k) {
        case k {
          " " -> SelectTool(Poke)
          _ -> Noop
        }
      }),
    ],
    [
      render_board(model),
      render_toolbar(model.selected_tool),
      html.div([], [
        html.text(case model.state {
          Playing -> ""
          GameOver(True) -> "You won!"
          GameOver(False) -> "You lost!"
        }),
      ]),
    ],
  )
}

const flag_cursor = "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg'  width='50' height='60' viewport='0 0 100 100' style='fill:black;font-size:30px;'><text y='50%'>🚩</text></svg>\") 16 0,auto /*!emojicursor.app*/"

const poke_cursor = "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg'  width='50' height='60' viewport='0 0 100 100' style='fill:black;font-size:30px;'><text y='50%'>👆</text></svg>\") 16 0,auto /*!emojicursor.app*/"

pub fn render_board(model: Model) {
  let tiles =
    list.range(1, board_size)
    |> list.map(fn(y) {
      // html.div(
      //   [attribute.style([#("display", "flex"), #("gap", "1px")])],
      list.range(1, board_size)
      |> list.map(fn(x) {
        case dict.get(model.board, Coord(x, y)) {
          Ok(_) -> Nil
          Error(_) -> {
            console.log(
              "Error getting tile at " <> coord_to_string(Coord(x, y)),
            )
          }
        }
        let assert Ok(t) = dict.get(model.board, Coord(x, y))

        render_tile(t, Coord(x, y))
      })
      // )
    })
    |> list.flatten()

  // let inner =
  // map_over_board(fn(x, y) {
  //   let assert Ok(t) = dict.get(model.board, Coord(x, y))
  //   render_tile(t)
  // })

  html.div(
    [
      attribute.style([
        #("display", "grid"),
        #(
          "grid-template-rows",
          "repeat(" <> int.to_string(board_size) <> "," <> tile_size <> ")",
        ),
        #(
          "grid-template-columns",
          "repeat(" <> int.to_string(board_size) <> "," <> tile_size <> ")",
        ),
        #("gap", "4px"),
        #("cursor", case model.selected_tool {
          Flag -> flag_cursor
          Poke -> poke_cursor
        }),
      ]),
    ],
    tiles,
  )
}

pub fn render_toolbar(selected_tool: Tool) {
  let toolbar_item = fn(tool: Tool, is_active: Bool) {
    let classes = [
      attribute.class("p-2"),
      attribute.classes([
        #("bg-blue-100", is_active),
        #("hover:bg-gray-100", !is_active),
      ]),
    ]
    case tool {
      Poke ->
        html.button([event.on_click(SelectTool(Poke)), ..classes], [
          html.text("👆"),
        ])
      Flag ->
        html.button([event.on_click(SelectTool(Flag)), ..classes], [
          html.text("🚩"),
        ])
    }
  }
  html.div(
    [
      attribute.class(
        "flex border rounded w-fit overflow-hidden last:border-l text-3xl",
      ),
    ],
    list.map(all_tools, fn(t) { toolbar_item(t, t == selected_tool) }),
  )
}

pub fn render_tile(tile_type: Tile, coord: Coord) -> Element(Msg) {
  let Tile(status, contents) = tile_type

  let icon = case status, contents {
    Unchecked, Bomb(_) -> "💣"
    Unchecked, Empty(0) | Checked, Empty(0) -> ""
    Unchecked, Empty(n) | Checked, Empty(n) -> int.to_string(n)
    Flagged, _ -> "🚩"
    Checked, Bomb(detonated: True) -> "💥"
    Checked, Bomb(detonated: False) -> "💣"
  }

  let revealed = case status {
    Unchecked -> False
    _ -> True
  }

  let final_icon = case revealed {
    True -> icon
    False -> ""
  }

  html.div(
    [
      attribute.class(
        "w-12 h-12 border border-gray-400 flex items-center justify-center text-3xl relative",
      ),
      attribute.classes([#("bg-gray-200 hover:bg-gray-300", !revealed)]),
      attribute.attribute(
        "data-coord",
        int.to_string(coord.x) <> "," <> int.to_string(coord.y),
      ),
      event.on_click(SelectTile(coord)),
    ],
    [
      html.text(final_icon),
      // html.span([attribute.class("text-sm top-0 left-0 absolute")], [
    //   html.text(coord_to_string(coord)),
    // ]),
    ],
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    Noop -> model
    SelectTile(coord) -> {
      case model.selected_tool {
        Poke -> poke_tile(model, coord)
        Flag -> flag_tile(model, coord)
      }
    }
    SelectTool(tool) -> Game(..model, selected_tool: tool)
  }
}

fn poke_tile(model: Model, coord: Coord) -> Model {
  let assert Ok(tile) = dict.get(model.board, coord)

  case tile.status, tile.contents {
    Unchecked, Bomb(_) -> {
      let new_tile = Tile(Checked, Bomb(detonated: True))
      let new_board =
        dict.insert(model.board, coord, new_tile)
        |> reveal_all_bombs
      Game(..model, board: new_board, state: GameOver(won: False))
    }
    Unchecked, Empty(_) -> {
      let new_tile = Tile(Checked, tile.contents)
      let new_board =
        dict.insert(model.board, coord, new_tile)
        |> list.fold(over: neighbors(coord), with: fn(board, c) {
          reveal_adjacent_safe_tiles(board, c)
        })

      let is_over = count_unchecked_non_bomb_tiles(new_board) == 0
      let state = case is_over {
        True -> GameOver(won: True)
        False -> Playing
      }

      Game(..model, board: new_board, state: state)
    }
    _, _ -> model
  }
}

fn reveal_all_bombs(board: Board) -> Board {
  fold_over_board(board, fn(board, x, y) {
    let assert Ok(tile) = dict.get(board, Coord(x, y))

    case tile.status, tile.contents {
      Unchecked, Bomb(_) -> {
        let new_tile = Tile(Checked, tile.contents)
        dict.insert(board, Coord(x, y), new_tile)
      }
      _, _ -> board
    }
  })
}

fn coord_to_string(c: Coord) {
  int.to_string(c.x) <> "," <> int.to_string(c.y)
}

fn neighbors(c: Coord) {
  let Coord(x, y) = c
  [
    // N
    Coord(x, y - 1),
    // NE
    Coord(x + 1, y - 1),
    // E
    Coord(x + 1, y),
    // SE
    Coord(x + 1, y + 1),
    // S
    Coord(x, y + 1),
    // SW
    Coord(x - 1, y + 1),
    // W
    Coord(x - 1, y),
    // NW
    Coord(x - 1, y - 1),
  ]
}

fn reveal_adjacent_safe_tiles(board: Board, coord: Coord) -> Board {
  case dict.get(board, coord) {
    Ok(tile) -> {
      case tile.status, tile.contents {
        Unchecked, Empty(_) -> {
          let new_tile = Tile(Checked, tile.contents)
          let board = dict.insert(board, coord, new_tile)

          case neighbor_bomb_count(board, coord) {
            0 ->
              board
              |> list.fold(over: neighbors(coord), with: fn(board, c) {
                reveal_adjacent_safe_tiles(board, c)
              })
            _ -> board
          }
        }
        _, _ -> board
      }
    }
    Error(_) -> board
  }
}

fn flag_tile(model: Model, coord: Coord) -> Model {
  let assert Ok(tile) = dict.get(model.board, coord)
  let new_tile = case tile.status {
    Unchecked -> Tile(Flagged, tile.contents)
    Flagged -> Tile(Unchecked, tile.contents)
    _ -> tile
  }

  let new_board = dict.insert(model.board, coord, new_tile)
  Game(..model, board: new_board)
}

fn count_unchecked_non_bomb_tiles(board: Board) -> Int {
  list.fold(over_board_coords(), from: 0, with: fn(acc, c) {
    let assert Ok(tile) = dict.get(board, c)
    case tile.status, tile.contents {
      Unchecked, Empty(_) -> acc + 1
      _, _ -> acc
    }
  })
}
