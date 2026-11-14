// Files bundled as plain text (see "rules" in wrangler.jsonc).
declare module "*.lua" {
  const text: string;
  export default text;
}
declare module "*.toc" {
  const text: string;
  export default text;
}
declare module "*.txt" {
  const text: string;
  export default text;
}
