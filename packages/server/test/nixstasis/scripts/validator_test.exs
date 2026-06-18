defmodule Nixstasis.Scripts.ValidatorTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Scripts.Validator

  test "renders canonical stary content" do
    rendered =
      Validator.render_stary(
        %{"name" => "demo", "schema" => %{"type" => "object"}, "version" => "1"},
        "def main():\n  return {}\n"
      )

    assert rendered =~ "---\n"
    assert rendered =~ "name: demo"
    assert rendered =~ "schema:\n  type: object"
    assert rendered =~ "def main():"
  end

  test "validates a representative stary document" do
    content = """
    ---
    name: demo
    version: "1"
    schema:
      type: object
      properties:
        value:
          type: string
    ---

    def main():
        return {"value": "ok"}
    """

    assert {:ok, %{front_matter: fm, body: body, rendered_content: rendered}} = Validator.validate_content(content)
    assert fm["name"] == "demo"
    assert body =~ "def main()"
    assert rendered =~ "name: demo"
  end

  test "rejects missing body" do
    content = """
    ---
    name: demo
    schema:
      type: object
    ---
    """

    assert {:error, message} = Validator.validate_content(content)
    assert message =~ "script body"
  end

  test "rejects invalid front matter" do
    content = """
    ---
    name: ""
    schema:
      type: object
    ---

    def main():
        return {}
    """

    assert {:error, message} = Validator.validate_content(content)
    assert message =~ "name"
  end

  test "rejects non-map YAML front matter" do
    content = """
    ---
    - item1
    - item2
    ---

    def main():
        return {}
    """

    assert {:error, message} = Validator.validate_content(content)
    assert message =~ "front matter must decode to a map"
  end

  test "rejects missing front matter delimiters" do
    content = "name: demo\nschema:\n  type: object\n"

    assert {:error, message} = Validator.validate_content(content)
    assert message =~ "front matter must start with ---"
  end

  test "rejects non-object schema type" do
    content = """
    ---
    name: demo
    schema:
      type: string
    ---

    def main():
        return "ok"
    """

    assert {:error, message} = Validator.validate_content(content)
    assert message =~ "schema type must be object"
  end

  test "accepts schema without type field" do
    content = """
    ---
    name: demo
    schema:
      properties:
        value:
          type: string
    ---

    def main():
        return {"value": "ok"}
    """

    assert {:ok, _} = Validator.validate_content(content)
  end

  test "rejects missing name in front matter" do
    content = """
    ---
    schema:
      type: object
    ---

    def main():
        return {}
    """

    assert {:error, message} = Validator.validate_content(content)
    assert message =~ "name"
  end

  test "rejects missing schema in front matter" do
    content = """
    ---
    name: demo
    ---

    def main():
        return {}
    """

    assert {:error, message} = Validator.validate_content(content)
    assert message =~ "schema"
  end

  test "rejects non-string version" do
    content = """
    ---
    name: demo
    version: 123
    schema:
      type: object
    ---

    def main():
        return {}
    """

    assert {:error, message} = Validator.validate_content(content)
    assert message =~ "version"
  end

  test "accepts content with BOM" do
    content = "\uFEFF---\nname: demo\nschema:\n  type: object\n---\n\ndef main():\n    return {}\n"

    assert {:ok, %{front_matter: fm}} = Validator.validate_content(content)
    assert fm["name"] == "demo"
  end
end
