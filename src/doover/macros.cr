module Doover
  # Internal annotation used to carry a `do_over` declaration from the macro
  # to the `finished` hook that emits the wrapped method.
  annotation Declaration
  end

  # Declares retry behavior for an instance method.
  #
  # The declaration may appear before or after the method definition. The
  # wrapper preserves the original method signature and forwards through
  # `previous_def`.
  #
  # ```
  # class A
  #   include Doover
  #
  #   do_over method: :fetch,
  #     strategy: :exponential,
  #     attempts: 3,
  #     delay: 100.milliseconds,
  #     on_retry: :handle_retry,
  #     on_exhausted: :handle_exhausted
  #
  #   def fetch
  #     # ...
  #   end
  #
  #   private def handle_retry(error : Exception, attempt : Int32) : Bool
  #     !error.is_a?(FatalError)
  #   end
  #
  #   private def handle_exhausted(error : Exception, attempts : Int32) : Nil
  #     Log.error { "gave up after #{attempts} attempts" }
  #   end
  # end
  # ```
  macro do_over(
    method,
    strategy = :exponential,
    attempts = 3,
    delay = 100.milliseconds,
    jitter = false,
    max_delay = nil,
    on_retry = nil,
    on_exhausted = nil,
    sleeper = nil,
    random = nil,
  )
    {% unless method.is_a?(SymbolLiteral) %}
      {% raise "do_over expects a symbol method name, e.g. `do_over method: :perform`" %}
    {% end %}

    {% method_name = method.id.stringify %}
    {% unless method_name =~ /^[A-Za-z_][A-Za-z0-9_]*[?!=]?$/ %}
      {% raise "do_over does not support operator method names (`#{method_name}`)" %}
    {% end %}

    {% strategy_name = strategy.is_a?(SymbolLiteral) ? strategy.id.stringify : nil %}
    {% unless ["exponential", "linear", "constant", "immediate"].includes?(strategy_name) %}
      {% raise "unknown do_over strategy `#{strategy}`; expected :exponential, :linear, :constant, or :immediate" %}
    {% end %}

    {% if on_retry && !on_retry.is_a?(SymbolLiteral) %}
      {% raise "do_over on_retry must be a method symbol or nil" %}
    {% end %}
    {% if on_exhausted && !on_exhausted.is_a?(SymbolLiteral) %}
      {% raise "do_over on_exhausted must be a method symbol or nil" %}
    {% end %}
    {% if sleeper && !sleeper.is_a?(SymbolLiteral) %}
      {% raise "do_over sleeper must be a method symbol or nil" %}
    {% end %}
    {% if random && !random.is_a?(SymbolLiteral) %}
      {% raise "do_over random must be a method symbol or nil" %}
    {% end %}

    {% suffix = method.id.stringify.gsub(/[^A-Za-z0-9_]/, "_") %}

    @[::Doover::Declaration(target: {{method}})]
    private def __doover_config_{{suffix.id}} : ::Doover::Config
      ::Doover.{{strategy.id}}
        .attempts({{attempts}})
        .delay({{delay}})
        .jitter({{jitter}})
        {% if max_delay %}
          .max_delay({{max_delay}})
        {% end %}
        {% if random %}
          .random({{random.id}})
        {% end %}
        {% if sleeper %}
          .sleep_with { |__doover_span| {{sleeper.id}}(__doover_span) }
        {% end %}
        {% if on_retry %}
          .on_retry { |__doover_error, __doover_attempt| {{on_retry.id}}(__doover_error, __doover_attempt) }
        {% end %}
        {% if on_exhausted %}
          .on_exhausted { |__doover_error, __doover_attempts| {{on_exhausted.id}}(__doover_error, __doover_attempts) }
        {% end %}
        .config
    end
  end

  macro included
    {% verbatim do %}
      macro finished
        {% seen_targets = [] of StringLiteral %}

        {% for config_method in @type.methods %}
          {% config_name = config_method.name.stringify %}
          {% if config_name.starts_with?("__doover_config_") %}
            {% declaration = config_method.annotation(::Doover::Declaration) %}
            {% if declaration %}
              {% target = declaration[:target] %}
              {% target_name = target.id.stringify %}

              {% if seen_targets.includes?(target_name) %}
                {% raise "duplicate do_over declaration for #{@type}##{target_name}" %}
              {% end %}
              {% seen_targets << target_name %}

              {% target_methods = @type.methods.select { |method| method.name == target.id } %}
              {% if target_methods.empty? %}
                {% raise "do_over target `#{target_name}` was not found as an instance method on #{@type}" %}
              {% end %}

              {% for method in target_methods %}
                {% if method.abstract? %}
                  {% raise "cannot wrap abstract method #{@type}##{method.name}" %}
                {% end %}

                {% captured_block = method.block_arg && method.block_arg.internal_name.stringify != "" %}
                {% if captured_block && !method.block_arg.restriction %}
                  {% raise "cannot wrap #{@type}##{method.name}: give the captured block parameter a type or use an anonymous `&` block" %}
                {% end %}

                {% if method.visibility == :private %}private{% elsif method.visibility == :protected %}protected{% end %} def {{method.name}}(
                  {% for argument, index in method.args %}
                    {% if method.splat_index && index == method.splat_index %}
                      *{{argument.internal_name}}{% if argument.restriction %} : {{argument.restriction}}{% end %},
                    {% else %}
                      {% if argument.name.stringify != argument.internal_name.stringify %}{{argument.name}} {% end %}{{argument.internal_name}}{% if argument.restriction %} : {{argument.restriction}}{% end %}{% if argument.default_value %} = {{argument.default_value}}{% end %},
                    {% end %}
                  {% end %}
                  {% if method.double_splat %}**{{method.double_splat.internal_name}}{% if method.double_splat.restriction %} : {{method.double_splat.restriction}}{% end %},{% end %}
                  {% if captured_block %}&__doover_block : {{method.block_arg.restriction}}{% elsif method.accepts_block? %}&{% end %}
                )
                  ::Doover.__doover_retry(__doover_config_{{config_name.gsub(/__doover_config_/, "").id}}) do
                    previous_def(
                      {% for argument, index in method.args %}
                        {% if method.splat_index && index == method.splat_index %}
                          {% if argument.internal_name.stringify != "" %}*{{argument.internal_name}},{% end %}
                        {% elsif !(method.splat_index && index > method.splat_index) %}
                          {{argument.internal_name}},
                        {% end %}
                      {% end %}
                      {% if method.double_splat %}**{{method.double_splat.internal_name}},{% end %}
                      {% for argument, index in method.args %}
                        {% if method.splat_index && index > method.splat_index %}
                          {{argument.name}}: {{argument.internal_name}},
                        {% end %}
                      {% end %}
                      {% if captured_block %}&__doover_block{% end %}
                    ){% if method.accepts_block? && !captured_block %} { |*__doover_block_args| yield *__doover_block_args }{% end %}
                  end
                end
              {% end %}
            {% end %}
          {% end %}
        {% end %}
      end
    {% end %}
  end
end
