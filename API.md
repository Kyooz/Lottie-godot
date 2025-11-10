# API Reference - Godot Lottie ThorVG

Esta documentação descreve a API completa dos nodes e recursos disponíveis na integração Godot Lottie ThorVG.

---

## LottieAnimation

**Herda:** `Node2D`

Um node que renderiza animações Lottie/dotLottie usando a engine ThorVG. Suporta playback, controle de velocidade, looping e renderização em tempo real de gráficos vetoriais.

### Propriedades

| Propriedade | Tipo | Descrição |
|------------|------|-----------|
| `animation_path` | `String` | Caminho para o arquivo de animação (`.json` ou `.lottie`). Aceita caminhos relativos ao projeto. |
| `playing` | `bool` | Se a animação está tocando atualmente. Pode ser alterado em runtime. |
| `autoplay` | `bool` | Se a animação deve começar automaticamente quando o node entra na árvore. |
| `looping` | `bool` | Se a animação deve repetir quando chegar ao fim. |
| `speed` | `float` | Velocidade de playback. 1.0 é velocidade normal, 2.0 é o dobro, 0.5 é metade. |
| `render_size` | `Vector2i` | Resolução de renderização da animação vetorial. Valores maiores oferecem melhor qualidade mas consomem mais memória. |

### Métodos

#### `void play()`

Inicia ou retoma a reprodução da animação.

```gdscript
lottie_node.play()
```

#### `void stop()`

Para a animação e reseta o frame atual para 0.

```gdscript
lottie_node.stop()
```

#### `void pause()`

Pausa a animação no frame atual.

```gdscript
lottie_node.pause()
```

#### `void seek(float frame)`

Pula para um frame específico da animação.

**Parâmetros:**
- `frame`: O número do frame (0 até `get_total_frames() - 1`)

```gdscript
lottie_node.seek(30)  # Pula para o frame 30
```

#### `void set_frame(float frame)`

Define o frame atual da animação. Equivalente a `seek()`.

#### `float get_frame()`

Retorna o frame atual da animação.

```gdscript
var current = lottie_node.get_frame()
print("Frame atual: ", current)
```

#### `float get_duration()`

Retorna a duração total da animação em segundos.

```gdscript
var duration = lottie_node.get_duration()
print("Duração: ", duration, " segundos")
```

#### `float get_total_frames()`

Retorna o número total de frames da animação.

```gdscript
var frames = lottie_node.get_total_frames()
print("Total de frames: ", frames)
```

### Sinais

#### `animation_finished()`

Emitido quando a animação termina (apenas se `looping` for `false`).

```gdscript
func _ready():
    lottie_node.animation_finished.connect(_on_animation_finished)

func _on_animation_finished():
    print("Animação terminou!")
```

#### `frame_changed(frame: float)`

Emitido sempre que o frame da animação muda.

**Parâmetros:**
- `frame`: O novo número do frame

```gdscript
func _ready():
    lottie_node.frame_changed.connect(_on_frame_changed)

func _on_frame_changed(frame: float):
    print("Novo frame: ", frame)
```

#### `animation_loaded(success: bool)`

Emitido quando uma animação é carregada.

**Parâmetros:**
- `success`: `true` se a animação foi carregada com sucesso, `false` caso contrário

```gdscript
func _ready():
    lottie_node.animation_loaded.connect(_on_animation_loaded)

func _on_animation_loaded(success: bool):
    if success:
        print("Animação carregada!")
    else:
        print("Falha ao carregar animação")
```

---

## LottieAnimationState

**Herda:** `Resource`

Define um estado de animação para uso em uma `LottieStateMachine`. Cada estado representa uma animação específica com suas configurações.

### Propriedades

| Propriedade | Tipo | Descrição |
|------------|------|-----------|
| `state_name` | `String` | Nome único do estado. |
| `animation_path` | `String` | Caminho para o arquivo de animação deste estado. |
| `loop` | `bool` | Se a animação deve fazer loop neste estado. |
| `speed` | `float` | Velocidade de playback para este estado. |
| `blend_time` | `float` | Tempo de transição (em segundos) ao entrar neste estado. |

---

## LottieStateTransition

**Herda:** `Resource`

Define uma transição entre dois estados em uma `LottieStateMachine`.

### Propriedades

| Propriedade | Tipo | Descrição |
|------------|------|-----------|
| `from_state` | `String` | Nome do estado de origem. |
| `to_state` | `String` | Nome do estado de destino. |
| `condition_parameter` | `String` | Nome do parâmetro usado para avaliar a condição. |
| `condition_value` | `Variant` | Valor esperado do parâmetro. |
| `condition_mode` | `String` | Modo de comparação: `"equals"`, `"not_equals"`, `"greater"`, `"less"`. |
| `transition_time` | `float` | Tempo de transição (em segundos). |
| `auto_advance` | `bool` | Se a transição deve ocorrer automaticamente quando o estado de origem terminar. |

### Métodos

#### `bool evaluate_condition(Dictionary parameters)`

Avalia se a condição da transição é satisfeita com base nos parâmetros fornecidos.

**Parâmetros:**
- `parameters`: Dicionário de parâmetros atuais

**Retorna:** `true` se a condição for satisfeita

---

## LottieStateMachine

**Herda:** `Resource`

Gerencia um sistema de state machine para animações Lottie, permitindo transições complexas entre diferentes animações baseadas em parâmetros e condições.

### Propriedades

| Propriedade | Tipo | Descrição |
|------------|------|-----------|
| `states` | `Array` | Array de `LottieAnimationState` disponíveis. |
| `transitions` | `Array` | Array de `LottieStateTransition` definidas. |
| `current_state` | `String` | Nome do estado atual. |
| `default_state` | `String` | Nome do estado inicial/padrão. |

### Métodos de Gerenciamento de Estados

#### `void add_state(LottieAnimationState state)`

Adiciona um novo estado à state machine.

```gdscript
var state = LottieAnimationState.new()
state.state_name = "idle"
state.animation_path = "res://animations/idle.json"
state_machine.add_state(state)
```

#### `void remove_state(String state_name)`

Remove um estado da state machine.

#### `LottieAnimationState get_state(String state_name)`

Retorna o estado com o nome especificado.

#### `Array get_all_states()`

Retorna todos os estados disponíveis.

#### `int get_state_count()`

Retorna o número de estados.

### Métodos de Gerenciamento de Transições

#### `void add_transition(LottieStateTransition transition)`

Adiciona uma nova transição à state machine.

```gdscript
var transition = LottieStateTransition.new()
transition.from_state = "idle"
transition.to_state = "walking"
transition.condition_parameter = "is_moving"
transition.condition_value = true
transition.condition_mode = "equals"
state_machine.add_transition(transition)
```

#### `void remove_transition(String from_state, String to_state)`

Remove uma transição específica.

#### `Array get_all_transitions()`

Retorna todas as transições disponíveis.

#### `int get_transition_count()`

Retorna o número de transições.

### Métodos de Controle

#### `void set_current_state(String state_name)`

Define o estado atual da state machine.

```gdscript
state_machine.set_current_state("walking")
```

#### `String get_current_state()`

Retorna o nome do estado atual.

#### `void set_parameter(String param_name, Variant value)`

Define o valor de um parâmetro usado para avaliar transições.

```gdscript
state_machine.set_parameter("is_moving", true)
state_machine.set_parameter("speed", 5.0)
```

#### `Variant get_parameter(String param_name)`

Retorna o valor de um parâmetro.

#### `Dictionary get_all_parameters()`

Retorna todos os parâmetros atuais.

#### `bool has_parameter(String param_name)`

Verifica se um parâmetro existe.

#### `void update(float delta, LottieAnimation animation_node)`

Atualiza a state machine. Deve ser chamado a cada frame, geralmente em `_process()`.

**Parâmetros:**
- `delta`: Tempo decorrido desde o último frame
- `animation_node`: O node `LottieAnimation` que será controlado

```gdscript
func _process(delta):
    state_machine.update(delta, lottie_node)
```

#### `void reset()`

Reseta a state machine para o estado padrão e limpa todos os parâmetros.

#### `bool is_in_blend()`

Retorna `true` se a state machine está atualmente em uma transição de blend.

#### `float get_blend_progress()`

Retorna o progresso da transição atual (0.0 a 1.0).

### Sinais

#### `state_changed(from_state: String, to_state: String)`

Emitido quando o estado muda.

#### `transition_started(from_state: String, to_state: String)`

Emitido quando uma transição começa.

#### `transition_finished(to_state: String)`

Emitido quando uma transição termina.

---

## Exemplo Completo de State Machine

```gdscript
extends Node2D

@onready var lottie_node = $LottieAnimation
var state_machine: LottieStateMachine

func _ready():
    # Criar state machine
    state_machine = LottieStateMachine.new()
    
    # Criar estados
    var idle_state = LottieAnimationState.new()
    idle_state.state_name = "idle"
    idle_state.animation_path = "res://animations/idle.json"
    idle_state.loop = true
    idle_state.speed = 1.0
    state_machine.add_state(idle_state)
    
    var walk_state = LottieAnimationState.new()
    walk_state.state_name = "walk"
    walk_state.animation_path = "res://animations/walk.json"
    walk_state.loop = true
    walk_state.speed = 1.0
    state_machine.add_state(walk_state)
    
    var jump_state = LottieAnimationState.new()
    jump_state.state_name = "jump"
    jump_state.animation_path = "res://animations/jump.json"
    jump_state.loop = false
    jump_state.speed = 1.0
    state_machine.add_state(jump_state)
    
    # Criar transições
    var idle_to_walk = LottieStateTransition.new()
    idle_to_walk.from_state = "idle"
    idle_to_walk.to_state = "walk"
    idle_to_walk.condition_parameter = "is_moving"
    idle_to_walk.condition_value = true
    idle_to_walk.condition_mode = "equals"
    state_machine.add_transition(idle_to_walk)
    
    var walk_to_idle = LottieStateTransition.new()
    walk_to_idle.from_state = "walk"
    walk_to_idle.to_state = "idle"
    walk_to_idle.condition_parameter = "is_moving"
    walk_to_idle.condition_value = false
    walk_to_idle.condition_mode = "equals"
    state_machine.add_transition(walk_to_idle)
    
    var any_to_jump = LottieStateTransition.new()
    any_to_jump.from_state = "idle"  # Você precisaria criar transições de cada estado
    any_to_jump.to_state = "jump"
    any_to_jump.condition_parameter = "jump_pressed"
    any_to_jump.condition_value = true
    any_to_jump.condition_mode = "equals"
    state_machine.add_transition(any_to_jump)
    
    var jump_to_idle = LottieStateTransition.new()
    jump_to_idle.from_state = "jump"
    jump_to_idle.to_state = "idle"
    jump_to_idle.auto_advance = true  # Transição automática quando a animação terminar
    state_machine.add_transition(jump_to_idle)
    
    # Definir estado padrão
    state_machine.set_default_state("idle")
    state_machine.reset()

func _process(delta):
    # Atualizar state machine
    state_machine.update(delta, lottie_node)

func _input(event):
    # Controlar parâmetros baseado em input
    if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left"):
        state_machine.set_parameter("is_moving", true)
    
    if event.is_action_released("ui_right") or event.is_action_released("ui_left"):
        state_machine.set_parameter("is_moving", false)
    
    if event.is_action_pressed("ui_up"):
        state_machine.set_parameter("jump_pressed", true)
    else:
        state_machine.set_parameter("jump_pressed", false)
```
