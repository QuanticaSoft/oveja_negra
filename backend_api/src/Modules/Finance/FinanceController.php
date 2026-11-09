<?php

declare(strict_types=1);

final class FinanceController
{
    public function expenseCategories(): never
    {
        Response::ok($this->categories()->list(['active' => Request::query('active')]));
    }

    public function createExpenseCategory(): never
    {
        Response::ok($this->categories()->create(Request::json()), 201);
    }

    public function updateExpenseCategory(string $id): never
    {
        $categoryId = Validation::positiveInt($id) ?? throw ApiException::notFound('Categoría de gasto no encontrada.');
        Response::ok($this->categories()->update($categoryId, Request::json()));
    }

    public function expenses(): never
    {
        $result = $this->expensesService()->list(QueryParams::only(['from', 'to', 'category_id', 'status', 'page', 'per_page']));
        Response::ok($result['data'], 200, $result['meta']);
    }

    /** 201 al crear; 200 si es un reintento con la misma Idempotency-Key. */
    public function createExpense(): never
    {
        $result = $this->expensesService()->create(Request::json(), Request::header(Idempotency::HEADER));
        Response::ok($result['expense'], $result['created'] ? 201 : 200);
    }

    public function voidExpense(string $id): never
    {
        $expenseId = Validation::positiveInt($id) ?? throw ApiException::notFound('Gasto no encontrado.');
        Response::ok($this->expensesService()->void($expenseId, Request::json()));
    }

    public function transactions(): never
    {
        $result = $this->finance()->transactions(QueryParams::only(['from', 'to', 'type', 'category', 'page', 'per_page']));
        Response::ok($result['data'], 200, $result['meta']);
    }

    public function summary(): never
    {
        Response::ok($this->finance()->summaryFromQuery(QueryParams::only(['from', 'to'])));
    }

    private function categories(): ExpenseCategoriesService
    {
        return new ExpenseCategoriesService(App::db(), App::user());
    }

    private function expensesService(): ExpensesService
    {
        return new ExpensesService(App::db(), App::user(), App::config()['business_day_cutoff']);
    }

    private function finance(): FinanceService
    {
        return new FinanceService(App::db(), App::config()['business_day_cutoff']);
    }
}
