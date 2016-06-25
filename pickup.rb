#! ruby -Ku
# coding: utf-8

require "uri"
require "natto"

COUNTS = [5, 7, 5, 7, 7]
PARENTHESES_LEFT  = ["「", "『"]
PARENTHESES_RIGHT = ["」", "』"]

def convert_text(text)
  texts = text.split("\n")
  texts -= [""]
  delete_lines = []
  texts.each do |line|
    delete_lines << line if /^\=\=.*\=\=$/ =~ line
  end
  texts -= delete_lines
  dicts = {}
  key = nil
  texts.each do |line|
    if /^\[\[(.*)\]\]$/ =~ line
      next if $1.include?("thumb")
      key = $1
      dicts[key] = {
        url: URI.escape("http://ja.wikipedia.org/wiki/#{key}"),
        texts: [],
      }
      next
    end
    dicts[key][:texts] << line
  end
  return dicts
end

def count_mora(word)
  return word.tr("ぁ-ゔ","ァ-ヴ").
         gsub(/[^アイウエオカ-モヤユヨラ-ロワヲンヴー]/, "").length
end

def convert_nodes(nm_nodes)
  nodes = []
  nm_nodes.each do |nm_node|
    next if [2, 3].include?(nm_node.stat)  # MECAB_BOS_NODE, MECAB_EOS_NODE
    features = nm_node.feature.split(",")
    if nm_node.stat == 1  # MECAB_UNK_NODE
      count = 0
    elsif features[0] == "記号"
      count = 0
    else
      count = count_mora(features[8])
    end
    nodes << {
      stat: nm_node.stat,
      surface: nm_node.surface,
      feature: {
        "品詞"        => features[0],
        "品詞細分類1" => features[1],
        "品詞細分類2" => features[2],
        "品詞細分類3" => features[3],
        "活用形1"     => features[4],
        "活用型2"     => features[5],
        "原形"        => features[6],
        "読み"        => features[7],
        "発音"        => features[8],
      },
      count: count,
    }
  end
  return nodes
end

def check_first_word(node, idx)
  return false if /^(助詞|助動詞)$/ =~ node[:feature]["品詞"]
  return false if /^(接尾|非自立)$/ =~ node[:feature]["品詞細分類1"]
  return false if "自立" == node[:feature]["品詞細分類1"] and
                  /^(する|できる)$/ =~ node[:feature]["原形"]
  return false if idx == 0 and
                  "フィラー" == node[:feature]["品詞"]
  return false if idx == 0 and
                  /^[、・　]$/ =~ node[:surface].scrub("")
  return true
end

def check_word(node, sum_count)
  return false if node[:stat] == 1
  return false if /[（）。…ゞ―：｜]/ =~ node[:surface].scrub("")
  return false if "アルファベット" == node[:feature]["品詞細分類1"]
  return false if sum_count != 0 and
                  /^[、・　]$/ =~ node[:surface].scrub("")
  return true
end

def check_tanka(tanka, next_node)
  # 括弧
  parentheses = [0] * PARENTHESES_LEFT.length
  tanka.each do |node|
    idx = PARENTHESES_LEFT.index(node[:surface])
    unless idx.nil?
      parentheses[idx] += 1
    end
    idx = PARENTHESES_RIGHT.index(node[:surface])
    unless idx.nil?
      parentheses[idx] -= 1
      return false if parentheses[idx] < 0
    end
  end
  return false unless parentheses == [0] * PARENTHESES_LEFT.length
  # 末尾
  return false if "連体詞" == tanka[-1][:feature]["品詞"]
  return false if /^(名詞接続|格助詞|係助詞|連体化|接続助詞|並立助詞|副詞化|数接続)$/ =~
                    tanka[-1][:feature]["品詞細分類1"]
  return false if "助動詞" == tanka[-1][:feature]["品詞"] and
                  "だ" == tanka[-1][:feature]["原形"]
  return false if !next_node.nil? and
                  !check_first_word(next_node, COUNTS.length)
  # OK
  return true
end

def find_tanka(texts)
  tankas = []
  texts.each do |text|
    nm_nodes = $nm.parse_as_nodes(text)
    nodes = convert_nodes(nm_nodes)
    nl = nodes.length
    (0...nl).each do |i|
      idx_count = 0
      sum_count = 0
      tanka = []
      (i...nl).each do |j|
        break if sum_count == 0 and !check_first_word(nodes[j], idx_count)
        break unless check_word(nodes[j], sum_count)
        sum_count += nodes[j][:count]
        tanka << nodes[j]
        if sum_count == COUNTS[idx_count]
          idx_count += 1
          if idx_count == COUNTS.length
            next_node = j < nl ? nodes[j + 1] : nil
            if check_tanka(tanka, next_node)
              tankas << { tanka: tanka, next_node: next_node }
            end
            break
          else
            sum_count = 0
          end
        elsif sum_count > COUNTS[idx_count]
          break
        end
      end
    end
  end
  return tankas
end

def print_tanka(tanka, key, url, next_node)
  # 短歌
  tanka.each do |node|
    STDOUT.print "#{node[:surface]}"
    STDERR.print "#{node[:surface]}"
  end
  STDOUT.puts ",#{key}"
  STDERR.puts ",#{key}"
  # デバッグ
  tanka.each do |node|
    STDERR.print "#{node[:surface]}"\
                 "【#{node[:count]},"\
                 "#{node[:feature]["品詞"]},"\
                 "#{node[:feature]["品詞細分類1"]},"\
                 "#{node[:feature]["品詞細分類2"]},"\
                 "#{node[:feature]["原形"]}】"
  end
  STDERR.print "#{next_node[:surface]}"\
               "《#{next_node[:count]},"\
               "#{next_node[:feature]["品詞"]},"\
               "#{next_node[:feature]["品詞細分類1"]},"\
               "#{next_node[:feature]["品詞細分類2"]},"\
               "#{next_node[:feature]["原形"]}》" unless next_node.nil?
  STDERR.puts
end

$nm = Natto::MeCab.new  # new 繰り返すとエラーになる
Dir::glob("./wp2txt/jawiki-latest-pages-articles.xml-*.txt").each {|f|
  # next unless /\.\/wp2txt\/jawiki-latest-pages-articles\.xml-001\.txt/ =~ f
  STDERR.puts f
  text = open(f).read
  dicts = convert_text(text)
  dicts.each do |key, value|
    tankas = find_tanka(value[:texts])
    tankas.each do |tanka|
      print_tanka(tanka[:tanka], key, value[:url], tanka[:next_node])
    end
  end
}
