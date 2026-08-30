# source: main.rb
# frozen_string_literal: true


# source: lib/backend.rb
# frozen_string_literal: true

class SuiteBackend
  SCORE_LABEL = "drift items"
  STATUSES = ["open", "tending", "complete"].freeze
  MAX_ITEMS = 128
  MAX_HISTORY = 256
  MAX_TEXT = 512
  MAX_STATE_BYTES = 262_144
  OUTPUT_LIMIT = 65_536

  Result = Struct.new(:stdout, :stderr, :exitstatus) do
    def success? = exitstatus.to_i.zero?
  end

  attr_reader :records

  def initialize(state_dir: File.expand_path("~/.local/state/omarchy-config-prism"), runner: nil)
    @state_dir = state_dir
    @state_path = File.join(state_dir, "state.json")
    @runner = runner
    @records = []
    @history = []
    @settings = {}
    @summary = "Starting"
    @score = 0
    create_directory(@state_dir)
    load_state
  end

  def snapshot
    {
      "items" => @records.first(MAX_ITEMS),
      "history" => @history.last(MAX_HISTORY),
      "summary" => clean(@summary, 100),
      "score" => @score.to_i,
      "updated_at" => Time.now.to_i
    }
  end

  def add(primary, secondary = "")
    title = clean(primary)
    detail = clean(secondary)
    return snapshot if title.empty?
    record = {
      "id" => "#{Time.now.to_i}-#{rand(1_000_000)}",
      "title" => title,
      "detail" => detail,
      "status" => STATUSES.first,
      "meta" => Time.now.strftime("%Y-%m-%d %H:%M")
    }
    after_add(record)
    @records.unshift(record)
    @records = @records.first(MAX_ITEMS)
    @score = @records.length
    @summary = "#{@records.length} #{SCORE_LABEL}"
    persist
    snapshot
  end

  def act(id)
    record = @records.find { |candidate| candidate["id"] == id.to_s }
    return snapshot unless record
    current = STATUSES.index(record["status"]) || 0
    record["status"] = STATUSES[(current + 1) % STATUSES.length]
    record["meta"] = "Updated #{Time.now.strftime("%Y-%m-%d %H:%M")}"
    persist
    snapshot
  end

  def remove(id)
    @records.reject! { |candidate| candidate["id"] == id.to_s }
    @score = @records.length
    @summary = @records.empty? ? "Ready" : "#{@records.length} #{SCORE_LABEL}"
    persist
    snapshot
  end

  def refresh
    scanned = scan_system
    @records = scanned if scanned.is_a?(Array)
    @records = @records.first(MAX_ITEMS)
    persist
    snapshot
  rescue StandardError => error
    @summary = "Needs attention"
    @records.unshift(item("Refresh issue", clean(error.message, 180), "inspect", "No system state was changed"))
    @records = @records.first(MAX_ITEMS)
    snapshot
  end

  private

  def after_add(record)
    record["status"] = STATUSES.first
    record
  end

  def scan_system
    pairs = [
      [File.expand_path("~/.config/hypr"), "/usr/share/omarchy/config/hypr"],
      [File.expand_path("~/.config/omarchy"), "/usr/share/omarchy/config/omarchy"]
    ]
    rows = []
    pairs.each do |user_root, stock_root|
      ignored = lambda do |relative|
        basename = File.basename(relative)
        relative.start_with?("plugins/") || relative.start_with?("themes/") ||
          basename.end_with?("~") || basename.include?(".bak") ||
          basename.end_with?(".backup") || basename.end_with?(".old")
      end
      user_files = relative_files(user_root).reject { |relative| ignored.call(relative) }
      stock_files = relative_files(stock_root).reject { |relative| ignored.call(relative) }
      (user_files + stock_files).uniq.sort.first(MAX_ITEMS).each do |relative|
        user_path = File.join(user_root, relative)
        stock_path = File.join(stock_root, relative)
        status = if File.file?(user_path) && File.file?(stock_path)
          safe_read(user_path) == safe_read(stock_path) ? "aligned" : "modified"
        elsif File.file?(user_path)
          "user only"
        else
          "stock only"
        end
        next if status == "aligned"
        rows << item(relative, "#{status} · #{short_path(user_root)}", status, "Review only — no files changed")
      end
    end
    @score = rows.length
    @summary = rows.empty? ? "Aligned" : "#{rows.length} drift"
    rows
  end

  def item(title, detail, status = "observed", meta = "")
    {
      "id" => fnv1a("#{title}:#{detail}:#{status}"),
      "title" => clean(title), "detail" => clean(detail),
      "status" => clean(status, 80), "meta" => clean(meta, 240)
    }
  end

  def run(argv, timeout: 8)
    return @runner.call(argv, timeout: timeout) if @runner
    OmarchyUI::Command.run(argv, timeout: timeout, max_output_bytes: OUTPUT_LIMIT)
  rescue Errno::ENOENT, OmarchyUI::CommandTimeout, OmarchyUI::CommandOutputLimit
    nil
  end

  def command_text(argv, timeout: 8)
    result = run(argv, timeout: timeout)
    return "" unless result && result.success?
    clean(result.stdout.to_s, OUTPUT_LIMIT)
  end

  def parse_json(text)
    return nil if text.nil? || text.empty? || text.bytesize > OUTPUT_LIMIT
    JSON.parse(text)
  rescue JSON::ParserError
    nil
  end

  def clean(value, limit = MAX_TEXT)
    value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�").byteslice(0, limit).to_s
  rescue StandardError
    value.to_s.byteslice(0, limit).to_s
  end

  def safe_read(path, limit = MAX_STATE_BYTES)
    return nil unless File.file?(path)
    File.open(path, "rb") do |file|
      data = file.read(limit + 1)
      return nil if data && data.bytesize > limit
      data
    end
  rescue SystemCallError
    nil
  end

  def relative_files(root)
    return [] unless File.directory?(root)
    result = []
    queue = [[root, ""]]
    until queue.empty? || result.length >= 2_000
      absolute, relative = queue.shift
      Dir.children(absolute).sort.first(512).each do |entry|
        next if entry == ".git" || entry == "node_modules" || entry == "vendor"
        child = File.join(absolute, entry)
        rel = relative.empty? ? entry : File.join(relative, entry)
        if File.directory?(child) && !File.symlink?(child)
          queue << [child, rel]
        elsif File.file?(child)
          result << rel
        end
      rescue SystemCallError
        next
      end
    end
    result
  end

  def executable?(name)
    return false if name.to_s.include?(File::SEPARATOR)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
      path = File.join(directory, name.to_s)
      File.respond_to?(:executable?) ? File.executable?(path) : File.file?(path)
    end
  end

  def secure_equal?(left, right)
    return false unless left.bytesize == right.bytesize
    difference = 0
    left.bytes.zip(right.bytes) { |a, b| difference |= a ^ b }
    difference.zero?
  end

  def fnv1a(value)
    hash = 2_166_136_261
    value.to_s.each_byte { |byte| hash = ((hash ^ byte) * 16_777_619) & 0xffff_ffff }
    format("%08x", hash)
  end

  def percent(part, whole)
    return 0 if whole.to_i <= 0
    [[(part.to_f / whole.to_f * 100).round, 0].max, 100].min
  end

  def human_bytes(bytes)
    value = bytes.to_f
    units = %w[B KiB MiB GiB TiB]
    unit = units.shift
    while value >= 1024 && !units.empty?
      value /= 1024.0
      unit = units.shift
    end
    "#{value.round(value >= 10 ? 0 : 1)} #{unit}"
  end

  def human_duration(seconds)
    days = seconds.to_f / 86_400
    return "#{days.round} days" if days < 365
    "#{(days / 365).round(1)} years"
  end

  def short_path(path)
    home = File.expand_path("~")
    path.start_with?(home) ? path.sub(home, "~") : path
  end

  def create_directory(path)
    current = path.start_with?(File::SEPARATOR) ? File::SEPARATOR : ""
    path.split(File::SEPARATOR).each do |part|
      next if part.empty?
      current = File.join(current, part)
      Dir.mkdir(current, 0o700) unless File.directory?(current)
    end
  end

  def load_state
    return unless File.file?(@state_path) && !File.symlink?(@state_path)
    data = safe_read(@state_path)
    parsed = data ? JSON.parse(data) : {}
    @records = Array(parsed["records"]).filter_map { |record| normalize_record(record) }.first(MAX_ITEMS)
    @history = Array(parsed["history"]).select { |entry| entry.is_a?(Hash) }.last(MAX_HISTORY)
    @settings = parsed["settings"].is_a?(Hash) ? parsed["settings"] : {}
    @score = @records.length
    @summary = @records.empty? ? "Ready" : "#{@records.length} #{SCORE_LABEL}"
  rescue JSON::ParserError, SystemCallError
    @records = []; @history = []; @settings = {}
  end

  def normalize_record(record)
    return nil unless record.is_a?(Hash)
    title = clean(record["title"])
    return nil if title.empty?
    {
      "id" => clean(record["id"], 80), "title" => title,
      "detail" => clean(record["detail"]), "status" => clean(record["status"], 80),
      "meta" => clean(record["meta"], 240), "evidence" => record["evidence"].is_a?(Hash) ? record["evidence"] : nil
    }.compact
  end

  def persist
    payload = JSON.generate("records" => @records.first(MAX_ITEMS), "history" => @history.last(MAX_HISTORY), "settings" => @settings)
    raise "state exceeds safety limit" if payload.bytesize > MAX_STATE_BYTES
    temporary = "#{@state_path}.tmp-#{Process.pid}-#{rand(1_000_000)}"
    File.open(temporary, "w", 0o600) { |file| file.write(payload) }
    File.rename(temporary, @state_path)
  ensure
    File.delete(temporary) if temporary && File.file?(temporary)
  end
end


backend = SuiteBackend.new

OmarchyUI.plugin do
  state :snapshot, backend.snapshot
  state :primary, ""
  state :secondary, ""
  state :compose, false

  refresh = proc do
    state.snapshot = backend.refresh
  rescue StandardError
    state.snapshot = backend.snapshot
  end

  status_color = lambda do |status|
    value = status.to_s.downcase
    danger = false
    healthy = false
    %w[broken critical missing mismatch drift inactive slow tight hotspot invalid].each do |token|
      danger = true if value.include?(token)
    end
    %w[ready valid verified finished aligned unique internal familiar steady covered available detected normal].each do |token|
      healthy = true if value.include?(token)
    end
    if danger
      "#ff6b78"
    elsif healthy
      "#9b8cff"
    else
      "#efc66b"
    end
  end

  status_icon = lambda do |status|
    value = status.to_s.downcase
    danger = false
    healthy = false
    %w[broken critical missing mismatch drift inactive slow tight hotspot invalid].each do |token|
      danger = true if value.include?(token)
    end
    %w[ready valid verified finished aligned unique internal familiar steady covered available detected normal].each do |token|
      healthy = true if value.include?(token)
    end
    if danger
      :warning
    elsif healthy
      :circle_check
    else
      :circle_info
    end
  end

  first_number = lambda do |value|
    number = 0
    value.to_s.split.each do |token|
      candidate = token.to_i
      if candidate > 0
        number = candidate
        break
      end
    end
    number
  end

  bar_widget do
    row spacing: 7 do
      icon :code, color: "#9b8cff"
      text { state.snapshot.fetch("summary") }
    end
    on_click { open_panel :config_prism }
  end

  panel :config_prism do
    scroll width: 660, height: 760 do
      dynamic id: :scene, spacing: 16 do
        entries = state.snapshot.fetch("items")
        history = state.snapshot.fetch("history")

        row spacing: 12 do
          icon :code, size: 30, color: "#9b8cff"
          column spacing: 2 do
            text "Config Prism", style: :heading, width: 500
            text state.snapshot.fetch("summary"), style: :caption, width: 500
          end
          action_button :refresh, tooltip: "Refresh", foreground: "#9b8cff" do
            async(&refresh)
          end
        end

        separator
        modified = entries.count { |entry| entry.fetch("status", "") == "modified" }
            user_only = entries.count { |entry| entry.fetch("status", "") == "user only" }
            stock_only = entries.count { |entry| entry.fetch("status", "") == "stock only" }
            row spacing: 24 do
              column spacing: 0 do
                text state.snapshot.fetch("score").to_s.rjust(2, "0"), size: 44, bold: true, color: "#9b8cff"
                text "configuration differences", style: :caption
              end
              bar_chart [modified, user_only, stock_only], labels: ["modified", "user", "stock"], width: 420, height: 94,
                colors: ["#9b8cff", "#efc66b", "#7da7ff"], show_grid: false, bar_spacing: 18
            end
            row spacing: 18 do
              text "#{modified} modified", style: :caption, color: "#9b8cff"
              text "#{user_only} user-only", style: :caption
              text "#{stock_only} stock-only", style: :caption
            end
            separator
            section_header "Configuration drift"
            if entries.empty?
              column spacing: 8 do
                        icon :code, size: 34, color: "#9b8cff"
                        text "Nothing to show yet", style: :heading
                        text "Your live configuration currently matches the packaged baseline.", style: :caption, wrap: true, width: 560
                      end
            else
              entries.first(16).each_with_index do |entry, index|
                row spacing: 10 do
                  icon status_icon.call(entry.fetch("status", "")), size: 15, color: status_color.call(entry.fetch("status", ""))
                  column spacing: 2 do
                    text entry.fetch("title"), width: 430, wrap: true
                    text entry.fetch("detail", ""), style: :caption, width: 430
                  end
                  text entry.fetch("status", ""), style: :caption, color: status_color.call(entry.fetch("status", ""))
                end
                separator unless index == [entries.length, 16].min - 1
              end
            end
      end
    end
  end

  after(0.08, &refresh)
  every(45, &refresh)
end
