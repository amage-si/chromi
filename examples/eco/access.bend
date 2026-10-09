import Base
import ./ui.bend as U
import ../../../Auvia/model.bend as AM
import ../../../Auvia/kairo.bend as AK
import ../../../Auvia/field.bend as AF
import ../../../Mokko/main.bend as Mk
import ../../../Mokko/field.bend as FL
import ../../../Kairo/types.bend as KT
import ../../../Tessra/geometry.bend as TG

# The demo as assistive technologies see it (Auvia): the window's frame,
# the Mokko button, the status line it updates, the Mokko text field with
# its text, caret and selection, and the field's note (its hint, or why an
# edit was refused). Kairo's state gives focus and press; the field's
# EditState gives the text. The status line and the note are polite live
# regions, so a screen reader announces an activation or a refusal even
# while focus is elsewhere.

def app_name() -> String:
  "amage-eco"

# Above every layout child id, so it never collides with a control.
def frame_id() -> U32:
  100

def status_id() -> U32:
  5

# What Mokko does not carry yet: the button's description and key, and
# which node controls or describes which.
def notes() -> List<&2, AK.Note>:
  [AK.Note{U.button_id(), "Conta uma ativação", [AM.Relation{AM.ControllerFor{}, [status_id()]}], Nil{}, "space"},
    AK.Note{status_id(), "", [AM.Relation{AM.ControlledBy{}, [U.button_id()]}], [AM.Attr{"live", "polite"}], ""},
    AK.Note{U.field_id(), "", [AM.Relation{AM.DescribedBy{}, [U.note_id()]}], Nil{}, ""},
    AK.Note{U.note_id(), "", [AM.Relation{AM.DescriptionFor{}, [U.field_id()]}], [AM.Attr{"live", "polite"}], ""}]

def label(+id: U32, text: String, r: TG.Rect) -> Mk.Semantic:
  Mk.Semantic{id, KT.TextRole{}, text, r, True{}, False{}, False{}, Nil{}}

# In reading order, which is also Kairo's Tab order for the two controls.
def semantics(+m: U.Model) -> List<&2, Mk.Semantic>:
  +k = U.kairo(m)
  [Mk.semantic(U.button_node(U.button_at(m)), k), label(status_id(), U.status(U.clicks(m)), U.status_at(m)),
    Mk.semantic(U.field_node(U.field_at(m)), k), label(U.note_id(), U.note_of(m), U.note_at(m))]

def contents(r: Result<&2, &2, String, FL.FieldView>) -> List<&2, AK.Content>:
  match r:
    case Fail{e}:
      Nil{}
    case Done{FL.FieldView{v, e}}:
      [AF.content(e)]

def surface(title: String, size: U32 & U32, active: Bool) -> AK.Surface:
  (w, h) = size
  AK.Surface{frame_id(), title, U32.to_f32(w), U32.to_f32(h), active}

# The tree to publish for the model, in a window titled `title` that has
# the keyboard focus when `active`.
def tree(+m: U.Model, title: String, active: Bool) -> AM.Tree:
  AK.build.with(app_name(), surface(title, U.size_of(m), active), semantics(m), notes(),
    contents(FL.view(U.field_node(U.field_at(m)), U.kairo(m), U.field_of(m), U.field_px(), FL.field_theme(), U.placeholder())))
